using System.ComponentModel.DataAnnotations;
using System.Data;
using Attendance.Api.Data;
using Attendance.Api.Entities;
using Attendance.Api.Middleware;
using Microsoft.EntityFrameworkCore;

namespace Attendance.Api.Services;

public sealed record LeaveDto(DateOnly FromDate, DateOnly ToDate, string Kind,
    [Required, StringLength(1000, MinimumLength = 5)] string Reason, DateTimeOffset? ShiftStartUtc = null, string? Half = null);
public sealed class LeaveService(AttendanceDbContext db, TimesheetService timesheets, AuditService audit)
{
    public static (DateTimeOffset Start, DateTimeOffset End) ExpectedWindow(DateTimeOffset start, DateTimeOffset end, IEnumerable<(DateTimeOffset Start, DateTimeOffset End)> intervals)
    {
        var ordered = intervals.OrderBy(x => x.Start).ToList();
        foreach (var interval in ordered) if (interval.Start <= start && interval.End > start) start = interval.End;
        foreach (var interval in ordered.AsEnumerable().Reverse()) if (interval.End >= end && interval.Start < end) end = interval.Start;
        return (start, end);
    }
    public async Task<object> List(Guid? employee, Guid? department, string? status, DateOnly? from, DateOnly? to, int page, int size, CancellationToken ct)
    {
        var q = db.LeaveRequests.AsNoTracking().AsQueryable();
        if (employee.HasValue) q = q.Where(x => x.EmployeeId == employee);
        if (department.HasValue) q = q.Where(x => x.Employee.DepartmentId == department);
        if (!string.IsNullOrEmpty(status)) q = q.Where(x => x.Status == status);
        if (from.HasValue) q = q.Where(x => x.ToDate >= from);
        if (to.HasValue) q = q.Where(x => x.FromDate <= to);
        return await Paging.Page(q.OrderByDescending(x => x.CreatedAtUtc).Select(x => new {
            x.Id, x.EmployeeId, employeeName = x.Employee.FullName, employeeCode = x.Employee.EmployeeCode,
            x.FromDate, x.ToDate, x.Kind, x.FromUtc, x.ToUtc, x.Reason, x.Status, x.DecisionReason,
            x.ReviewedByUserId, x.ReviewedAtUtc, x.CreatedAtUtc, rowVersion = x.RowVersion
        }), page, size, ct);
    }
    public async Task<object> Save(Guid? id, Guid employee, LeaveDto d, Guid actor, CancellationToken ct)
    {
        if (d.ToDate < d.FromDate || d.ToDate.DayNumber - d.FromDate.DayNumber > 92 || d.FromDate.Year < 2000 || d.ToDate.Year > 2100)
            throw new ApiException(400, "InvalidDateRange", "Chọn khoảng nghỉ tối đa 93 ngày.");
        TimesheetService.RequireReason(d.Reason);
        if (d.Kind is not ("FullDay" or "HalfDay") || d.Kind == "HalfDay" && (d.FromDate != d.ToDate || d.Half is not ("First" or "Second") || d.ShiftStartUtc is null))
            throw new ApiException(400, "InvalidLeave", "Nghỉ nửa ngày cần chọn một ngày, ca và nửa đầu/nửa cuối ca.");
        await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct); await TimesheetGuard.Lock(db, ct);
        var item = id.HasValue ? await db.LeaveRequests.SingleOrDefaultAsync(x => x.Id == id && x.EmployeeId == employee, ct) ?? throw CatalogService.Missing() : new LeaveRequest { EmployeeId = employee };
        if (item.Status != "Pending") throw new ApiException(409, "LeaveReviewed", "Chỉ được sửa đơn đang chờ duyệt.");
        var lines = new List<WorkLine>();
        for (var m = new DateOnly(d.FromDate.Year, d.FromDate.Month, 1); m <= d.ToDate; m = m.AddMonths(1))
            lines.AddRange((await timesheets.Calculate(m.Year, m.Month, employee, null, null, ct)).SelectMany(x => x.Lines).Where(x => x.Date >= d.FromDate && x.Date <= d.ToDate));
        if (lines.Count == 0) throw new ApiException(409, "NoScheduledShift", "Khoảng nghỉ chưa có lịch làm việc. Hãy liên hệ Admin.");
        item.FromDate = d.FromDate; item.ToDate = d.ToDate; item.Kind = d.Kind; item.Reason = d.Reason.Trim();
        item.FromUtc = null; item.ToUtc = null; item.EmployeeShiftId = null;
        if (d.Kind == "HalfDay")
        {
            var line = lines.SingleOrDefault(x => x.StartUtc == d.ShiftStartUtc) ?? throw new ApiException(409, "ShiftChanged", "Ca đã thay đổi. Hãy tải lại và chọn ca.");
            var middle = line.StartUtc.AddTicks((line.EndUtc - line.StartUtc).Ticks / 2);
            item.FromUtc = d.Half == "First" ? line.StartUtc : middle; item.ToUtc = d.Half == "First" ? middle : line.EndUtc;
            item.EmployeeShiftId = line.AssignmentId;
        }
        await ValidateOverlap(item, ct);
        if (!id.HasValue) db.Add(item);
        audit.Add(actor, "LeaveRequest", item.Id, id.HasValue ? "Updated" : "Created");
        await db.SaveChangesAsync(ct); await tx.CommitAsync(ct); return new { item.Id, item.Status };
    }
    private async Task ValidateOverlap(LeaveRequest item, CancellationToken ct)
    {
        var other = await db.LeaveRequests.AsNoTracking().Where(x => x.Id != item.Id && x.EmployeeId == item.EmployeeId &&
            (x.Status == "Pending" || x.Status == "Approved") && x.FromDate <= item.ToDate && x.ToDate >= item.FromDate).ToListAsync(ct);
        if (other.Any(x => x.Kind == "FullDay" || item.Kind == "FullDay" || x.FromUtc < item.ToUtc && x.ToUtc > item.FromUtc))
            throw new ApiException(409, "LeaveOverlap", "Khoảng nghỉ trùng đơn đang chờ hoặc đã được duyệt.");
    }
    public async Task<object> Decide(Guid id, Guid? ownEmployee, string status, string? reason, Guid actor, CancellationToken ct)
    {
        await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct); await TimesheetGuard.Lock(db, ct);
        var item = await db.LeaveRequests.SingleOrDefaultAsync(x => x.Id == id && (!ownEmployee.HasValue || x.EmployeeId == ownEmployee), ct) ?? throw CatalogService.Missing();
        if (ownEmployee.HasValue && status != "Cancelled") throw new ApiException(403, "Forbidden", "Không có quyền duyệt đơn.");
        if (item.Status != "Pending" && !(ownEmployee is null && item.Status == "Approved" && status == "Cancelled"))
            throw new ApiException(409, "LeaveReviewed", "Đơn không còn chờ xử lý.");
        if (!ownEmployee.HasValue) TimesheetService.RequireReason(reason);
        if (status == "Approved")
        {
            await ValidateOverlap(item, ct);
            var sheets = new List<WorkLine>();
            for (var m = new DateOnly(item.FromDate.Year, item.FromDate.Month, 1); m <= item.ToDate; m = m.AddMonths(1))
                sheets.AddRange((await timesheets.Calculate(m.Year, m.Month, item.EmployeeId, null, null, ct)).SelectMany(x => x.Lines).Where(x => x.Date >= item.FromDate && x.Date <= item.ToDate));
            if (sheets.Count == 0) throw new ApiException(409, "NoScheduledShift", "Không còn ca trong khoảng nghỉ.");
            if (item.Kind == "HalfDay" && !sheets.Any(x => x.StartUtc <= item.FromUtc && x.EndUtc >= item.ToUtc))
                throw new ApiException(409, "ShiftChanged", "Ca đã thay đổi. Nhân viên cần cập nhật đơn.");
            if (sheets.Any(x => x.CheckInUtc.HasValue && (item.Kind == "FullDay" || x.CheckInUtc < item.ToUtc && (!x.CheckOutUtc.HasValue || x.CheckOutUtc > item.FromUtc))))
                throw new ApiException(409, "AttendanceConflict", "Đã có chấm công chồng khoảng nghỉ. Cần đối chiếu, không được tính hai lần.");
        }
        var old = item.Status; item.Status = status; item.DecisionReason = reason?.Trim(); item.ReviewedAtUtc = DateTimeOffset.UtcNow; item.ReviewedByUserId = actor;
        audit.Add(actor, "LeaveRequest", id, status, new { oldStatus = old, reason });
        await db.SaveChangesAsync(ct); await tx.CommitAsync(ct); return new { item.Id, item.Status };
    }
}
