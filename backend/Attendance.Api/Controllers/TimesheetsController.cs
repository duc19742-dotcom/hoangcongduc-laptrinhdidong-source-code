using System.ComponentModel.DataAnnotations;
using System.Data;
using Attendance.Api.Data;
using Attendance.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Attendance.Api.Controllers;

public sealed record PeriodActionDto([StringLength(1000)] string? Reason);
public sealed record TimesheetResponseDto([Required] string Status, [StringLength(1000)] string? Note);

[ApiController, Route("api/v1/timesheets"), Authorize]
public sealed class TimesheetsController(TimesheetService service, AttendanceService attendance, AttendanceDbContext db) : ControllerBase
{
    [HttpGet("{year:int}/{month:int}")]
    public async Task<object> Month(int year, int month, Guid? employeeId, Guid? departmentId, string? search, int page = 1, int pageSize = 20, CancellationToken ct = default)
    {
        if (!User.Admin()) { employeeId = await attendance.EmployeeId(User.UserId(), ct); departmentId = null; search = null; }
        return await service.Month(year, month, employeeId, departmentId, search, page, pageSize, ct);
    }
    [HttpPost("{year:int}/{month:int}/publish"), Authorize(Roles = "Admin")]
    public Task<object> Publish(int year, int month, CancellationToken ct) => service.Publish(year, month, User.UserId(), ct);
    [HttpPost("{year:int}/{month:int}/close"), Authorize(Roles = "Admin")]
    public Task<object> Close(int year, int month, PeriodActionDto d, CancellationToken ct) => service.Close(year, month, d.Reason, User.UserId(), ct);
    [HttpPost("{year:int}/{month:int}/reopen"), Authorize(Roles = "Admin")]
    public Task<object> Reopen(int year, int month, PeriodActionDto d, CancellationToken ct) => service.Reopen(year, month, d.Reason ?? "", User.UserId(), ct);
    [HttpPost("snapshots/{id:guid}/respond"), Authorize(Roles = "Employee")]
    public async Task<object> Respond(Guid id, TimesheetResponseDto d, CancellationToken ct) => await service.Respond(id, await attendance.EmployeeId(User.UserId(), ct), d.Status, d.Note, ct);
    [HttpPost("snapshots/{id:guid}/resolve"), Authorize(Roles = "Admin")]
    public Task<object> Resolve(Guid id, PeriodActionDto d, CancellationToken ct) => service.Resolve(id, d.Reason ?? "", User.UserId(), ct);
    [HttpGet("{year:int}/{month:int}/export"), Authorize(Roles = "Admin")]
    public async Task<IActionResult> Export(int year, int month, Guid? employeeId, Guid? departmentId, string? search, CancellationToken ct)
    {
        TimesheetService.MonthStart(year, month);
        await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct); await TimesheetGuard.Lock(db, ct);
        var period = await db.TimesheetPeriods.AsNoTracking().SingleOrDefaultAsync(x => x.Year == year && x.Month == month, ct);
        var sheets = period?.Status == "Closed" ? (await db.TimesheetSnapshots.AsNoTracking().Where(x => x.PeriodId == period.Id && x.Revision == period.Revision).ToListAsync(ct))
            .Select(TimesheetService.Read).Where(x => (!employeeId.HasValue || x.EmployeeId == employeeId) && (!departmentId.HasValue || x.DepartmentId == departmentId) &&
                (string.IsNullOrWhiteSpace(search) || x.EmployeeName.Contains(search, StringComparison.OrdinalIgnoreCase) || x.EmployeeCode.Contains(search, StringComparison.OrdinalIgnoreCase))).OrderBy(x => x.EmployeeCode).ToList() :
            await service.Calculate(year, month, employeeId, departmentId, search, ct);
        var status = period?.Status == "Closed" ? "Đã chốt" : "Nháp – dữ liệu hiện tại, chưa chốt";
        var bytes = TimesheetExport.Create(sheets, status, period?.Revision ?? 0, $"{month:00}/{year}; nhân viên: {employeeId?.ToString() ?? "Tất cả"}; phòng: {departmentId?.ToString() ?? "Tất cả"}; tìm: {search ?? ""}");
        await tx.CommitAsync(ct);
        return File(bytes, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", $"Bang-cong-{year}-{month:00}.xlsx");
    }
}

[ApiController, Route("api/v1/leave-requests"), Authorize]
public sealed class LeaveRequestsController(LeaveService service, AttendanceService attendance) : ControllerBase
{
    [HttpGet]
    public async Task<object> List(Guid? employeeId, Guid? departmentId, string? status, DateOnly? from, DateOnly? to, int page = 1, int pageSize = 20, CancellationToken ct = default)
    {
        if (!User.Admin()) { employeeId = await attendance.EmployeeId(User.UserId(), ct); departmentId = null; }
        return await service.List(employeeId, departmentId, status, from, to, page, pageSize, ct);
    }
    [HttpPost, Authorize(Roles = "Employee")]
    public async Task<object> Create(LeaveDto d, CancellationToken ct) => await service.Save(null, await attendance.EmployeeId(User.UserId(), ct), d, User.UserId(), ct);
    [HttpPut("{id:guid}"), Authorize(Roles = "Employee")]
    public async Task<object> Update(Guid id, LeaveDto d, CancellationToken ct) => await service.Save(id, await attendance.EmployeeId(User.UserId(), ct), d, User.UserId(), ct);
    [HttpPost("{id:guid}/{action}")]
    public async Task<object> Decide(Guid id, string action, PeriodActionDto d, CancellationToken ct)
    {
        var status = action switch { "approve" => "Approved", "reject" => "Rejected", "cancel" => "Cancelled", _ => throw CatalogService.Missing() };
        Guid? own = User.Admin() ? null : await attendance.EmployeeId(User.UserId(), ct);
        return await service.Decide(id, own, status, d.Reason, User.UserId(), ct);
    }
}

[ApiController, Route("api/v1/dashboard"), Authorize(Roles = "Admin")]
public sealed class DashboardController(TimesheetService timesheets, AttendanceDbContext db) : ControllerBase
{
    [HttpGet]
    public async Task<object> Get(DateOnly? date, Guid? departmentId, CancellationToken ct)
    {
        var day = date ?? DateOnly.FromDateTime(DateTime.UtcNow.AddHours(7));
        var sheets = await timesheets.Calculate(day.Year, day.Month, null, departmentId, null, ct);
        var previous = day.AddDays(-1);
        if (previous.Month != day.Month) sheets.AddRange(await timesheets.Calculate(previous.Year, previous.Month, null, departmentId, null, ct));
        var start = Geo.Utc(day, TimeOnly.MinValue);
        var rows = sheets.SelectMany(s => s.Lines.Where(l => l.Date == day || l.Date == previous && l.EndUtc > start)
            .Select(l => new { s.EmployeeId, s.EmployeeName, s.EmployeeCode, s.Department, line = l })).ToList();
        var pendingLeave = await db.LeaveRequests.CountAsync(x => x.Status == "Pending" && (!departmentId.HasValue || x.Employee.DepartmentId == departmentId), ct);
        var pendingAttendance = await db.AttendanceRequests.CountAsync(x => x.Status == "Pending" && (!departmentId.HasValue || x.Employee.DepartmentId == departmentId), ct);
        var pendingSupport = await db.Set<AttendanceSupport>().CountAsync(x => x.Status == "Pending" && (!departmentId.HasValue || db.Employees.Any(e => e.UserId == x.UserId && e.DepartmentId == departmentId)), ct);
        return new { date = day, departmentId, unit = "Ca làm (các nhóm có thể giao nhau)", scheduled = rows.Count, employees = rows.Select(x => x.EmployeeId).Distinct().Count(),
            checkIns = rows.Count(x => x.line.CheckInUtc.HasValue), checkOuts = rows.Count(x => x.line.CheckOutUtc.HasValue), late = rows.Count(x => x.line.LateMinutes > 0),
            missingIn = rows.Count(x => x.line.Status == "MissingCheckIn"), missingOut = rows.Count(x => x.line.Status == "MissingCheckOut"),
            onLeave = rows.Count(x => x.line.LeaveMinutes > 0), pendingLeave, pendingAttendance, pendingSupport, items = rows, serverTimeUtc = DateTimeOffset.UtcNow };
    }
}
