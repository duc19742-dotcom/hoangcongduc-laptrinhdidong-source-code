using System.Data;
using System.Text.Json;
using Attendance.Api.Data;
using Attendance.Api.Entities;
using Attendance.Api.Middleware;
using Microsoft.EntityFrameworkCore;

namespace Attendance.Api.Services;

public sealed record WorkLine(Guid? AssignmentId, Guid EmployeeId, DateOnly Date, string Shift, string Location,
    DateTimeOffset StartUtc, DateTimeOffset EndUtc, int GraceMinutes, DateTimeOffset? CheckInUtc,
    DateTimeOffset? CheckOutUtc, string? InSource, string? OutSource, Guid? InAttemptId, Guid? OutAttemptId,
    double? WorkedMinutes, double LeaveMinutes, int LateMinutes, int EarlyMinutes, string Status);
public sealed record EmployeeTimesheet(Guid EmployeeId, string EmployeeCode, string EmployeeName, Guid DepartmentId,
    string Department, int Year, int Month, List<WorkLine> Lines)
{
    public int ScheduledShifts => Lines.Count;
    public int ScheduledDays => Lines.Select(x => x.Date).Distinct().Count();
    public int AttendedDays => Lines.Where(x => x.CheckInUtc.HasValue).Select(x => x.Date).Distinct().Count();
    public double ConfirmedHours => Math.Round(Lines.Sum(x => x.WorkedMinutes ?? 0) / 60, 2);
    public double LeaveHours => Math.Round(Lines.Sum(x => x.LeaveMinutes) / 60, 2);
    public int MissingShifts => Lines.Count(x => x.Status is "MissingCheckIn" or "MissingCheckOut");
    public int LateShifts => Lines.Count(x => x.LateMinutes > 0);
    public int EarlyShifts => Lines.Count(x => x.EarlyMinutes > 0);
}

public sealed class TimesheetService(AttendanceDbContext db, AuditService audit)
{
    internal static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    public static DateOnly MonthStart(int year, int month)
    {
        if (year is < 2000 or > 2100 || month is < 1 or > 12) throw new ApiException(400, "InvalidMonth", "Tháng/năm không hợp lệ.");
        return new(year, month, 1);
    }
    public async Task<List<EmployeeTimesheet>> Calculate(int year, int month, Guid? employee, Guid? department, string? search, CancellationToken ct)
    {
        var from = MonthStart(year, month); var to = from.AddMonths(1).AddDays(-1);
        var q = db.Employees.AsNoTracking().Include(x => x.Department).Where(x => x.IsActive || db.EmployeeShifts.Any(s => s.EmployeeId == x.Id && s.WorkDate >= from && s.WorkDate <= to));
        if (employee.HasValue) q = q.Where(x => x.Id == employee);
        if (department.HasValue) q = q.Where(x => x.DepartmentId == department);
        if (!string.IsNullOrWhiteSpace(search)) q = q.Where(x => x.FullName.Contains(search) || x.EmployeeCode.Contains(search));
        var people = await q.OrderBy(x => x.EmployeeCode).ToListAsync(ct); var ids = people.Select(x => x.Id).ToList();
        var assignments = await db.EmployeeShifts.AsNoTracking().Include(x => x.Shift).Include(x => x.WorkLocation)
            .Where(x => ids.Contains(x.EmployeeId) && x.WorkDate >= from && x.WorkDate <= to).ToListAsync(ct);
        var schedules = await db.Set<WorkSchedule>().AsNoTracking().Include(x => x.Shift).Include(x => x.WorkLocation)
            .Where(x => x.IsActive && x.FromDate <= to && x.ToDate >= from && (x.EmployeeId == null || ids.Contains(x.EmployeeId.Value))).ToListAsync(ct);
        var assignmentIds = assignments.Select(x => x.Id).ToList();
        var records = await db.AttendanceRecords.AsNoTracking().Where(x => assignmentIds.Contains(x.EmployeeShiftId)).ToListAsync(ct);
        var leaves = await db.LeaveRequests.AsNoTracking().Where(x => ids.Contains(x.EmployeeId) && x.Status == "Approved" && x.FromDate <= to && x.ToDate >= from).ToListAsync(ct);
        var result = new List<EmployeeTimesheet>(); var now = DateTimeOffset.UtcNow;
        foreach (var person in people)
        {
            var lines = new List<WorkLine>();
            for (var day = from; day <= to; day = day.AddDays(1))
            {
                var daily = assignments.Where(x => x.EmployeeId == person.Id && x.WorkDate == day).ToList();
                if (daily.Count == 0 && person.IsActive && day >= person.HireDate)
                {
                    var bit = 1 << (int)day.DayOfWeek;
                    var schedule = schedules.Where(x => x.FromDate <= day && x.ToDate >= day && (x.WeekdaysMask & bit) != 0 &&
                        (x.EmployeeId == null || x.EmployeeId == person.Id) && x.Shift.IsActive && x.WorkLocation.IsActive)
                        .OrderByDescending(x => x.EmployeeId.HasValue).ThenByDescending(x => x.CreatedAtUtc).FirstOrDefault();
                    if (schedule is not null) daily.Add(new EmployeeShift { Id = Guid.Empty, EmployeeId = person.Id, WorkDate = day,
                        Shift = schedule.Shift, WorkLocation = schedule.WorkLocation, StartUtc = Geo.Utc(day, schedule.Shift.StartLocalTime),
                        EndUtc = Geo.Utc(day.AddDays(schedule.Shift.EndsNextDay ? 1 : 0), schedule.Shift.EndLocalTime), GraceMinutesSnapshot = schedule.Shift.LateGraceMinutes });
                }
                foreach (var shift in daily.OrderBy(x => x.StartUtc))
                {
                    var rs = records.Where(x => x.EmployeeShiftId == shift.Id).ToList();
                    var i = rs.SingleOrDefault(x => x.Action == "CheckIn"); var o = rs.SingleOrDefault(x => x.Action == "CheckOut");
                    var leaveIntervals = leaves.Where(x => x.EmployeeId == person.Id && x.FromDate <= day && x.ToDate >= day)
                        .Where(x => x.Kind == "FullDay" || x.FromUtc < shift.EndUtc && x.ToUtc > shift.StartUtc)
                        .Select(x => (Start: x.Kind == "FullDay" ? shift.StartUtc : x.FromUtc!.Value, End: x.Kind == "FullDay" ? shift.EndUtc : x.ToUtc!.Value))
                        .OrderBy(x => x.Start).ToList();
                    var leave = 0d; var cursor = shift.StartUtc; var overlap = false;
                    foreach (var interval in leaveIntervals)
                    {
                        var a = interval.Start > cursor ? interval.Start : cursor; var b = interval.End < shift.EndUtc ? interval.End : shift.EndUtc;
                        if (b > a) { leave += (b - a).TotalMinutes; cursor = b; }
                        if (i is not null && (o is null ? i.EffectiveAtUtc >= interval.Start && i.EffectiveAtUtc < interval.End :
                            i.EffectiveAtUtc < interval.End && o.EffectiveAtUtc > interval.Start)) overlap = true;
                    }
                    var (expectedStart, expectedEnd) = LeaveService.ExpectedWindow(shift.StartUtc, shift.EndUtc, leaveIntervals);
                    var fullLeave = leave >= (shift.EndUtc - shift.StartUtc).TotalMinutes;
                    var status = overlap ? "LeaveConflict" : fullLeave ? "Leave" : i is null ?
                        (now > expectedStart.AddMinutes(shift.GraceMinutesSnapshot) ? "MissingCheckIn" : "Scheduled") : o is null ?
                        (now > expectedEnd ? "MissingCheckOut" : "Working") : "Completed";
                    var late = i is not null && i.EffectiveAtUtc > expectedStart.AddMinutes(shift.GraceMinutesSnapshot) ? (int)Math.Ceiling((i.EffectiveAtUtc - expectedStart).TotalMinutes) : 0;
                    var early = o is not null && o.EffectiveAtUtc < expectedEnd ? (int)Math.Ceiling((expectedEnd - o.EffectiveAtUtc).TotalMinutes) : 0;
                    lines.Add(new(shift.Id == Guid.Empty ? null : shift.Id, person.Id, day, shift.Shift.Name, shift.WorkLocation.Name,
                        shift.StartUtc, shift.EndUtc, shift.GraceMinutesSnapshot, i?.EffectiveAtUtc, o?.EffectiveAtUtc, i?.Source, o?.Source,
                        i?.AttemptId, o?.AttemptId, i is not null && o is not null ? Math.Round(Math.Max(0, (o.EffectiveAtUtc - i.EffectiveAtUtc).TotalMinutes), 2) : null,
                        Math.Round(leave, 2), late, early, status));
                }
            }
            result.Add(new(person.Id, person.EmployeeCode, person.FullName, person.DepartmentId, person.Department.Name, year, month, lines));
        }
        return result;
    }
    internal static string Serialize(EmployeeTimesheet data) => JsonSerializer.Serialize(data, JsonOptions);
    internal static string Hash(EmployeeTimesheet data) => Secrets.Hash(Serialize(data));
    internal static EmployeeTimesheet Read(TimesheetSnapshot s) => JsonSerializer.Deserialize<EmployeeTimesheet>(s.DataJson, JsonOptions)!;

    public async Task<object> Month(int year, int month, Guid? employee, Guid? department, string? search, int page, int size, CancellationToken ct)
    {
        MonthStart(year, month); page = Math.Max(1, page); size = Math.Clamp(size, 1, 100);
        await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
        await TimesheetGuard.Lock(db, ct);
        var period = await db.TimesheetPeriods.AsNoTracking().SingleOrDefaultAsync(x => x.Year == year && x.Month == month, ct);
        var snapshots = period is null ? [] : await db.TimesheetSnapshots.AsNoTracking().Where(x => x.PeriodId == period.Id && x.Revision == period.Revision).ToListAsync(ct);
        var sheets = period?.Status == "Closed" ? snapshots.Select(Read).Where(x => (!employee.HasValue || x.EmployeeId == employee) &&
            (!department.HasValue || x.DepartmentId == department) && (string.IsNullOrWhiteSpace(search) || x.EmployeeName.Contains(search, StringComparison.OrdinalIgnoreCase) || x.EmployeeCode.Contains(search, StringComparison.OrdinalIgnoreCase))).ToList() :
            await Calculate(year, month, employee, department, search, ct);
        var items = sheets.OrderBy(x => x.EmployeeCode).Skip((page - 1) * size).Take(size).Select(x =>
        {
            var snapshot = snapshots.SingleOrDefault(s => s.EmployeeId == x.EmployeeId);
            var outdated = period?.Status == "Published" && x.Lines.Count > 0 && (snapshot is null || snapshot.ContentHash != Hash(x));
            return new { data = x, snapshotId = snapshot?.Id, responseStatus = outdated ? "Outdated" : snapshot?.ResponseStatus ?? "NotPublished",
                snapshot?.Feedback, snapshot?.Resolution, snapshot?.RespondedAtUtc, needsRepublish = outdated };
        });
        await tx.CommitAsync(ct);
        return new { items, totalCount = sheets.Count, page, pageSize = size, status = period?.Status ?? "Draft", revision = period?.Revision ?? 0,
            periodId = period?.Id, period?.ClosedAtUtc, period?.ExceptionReason, serverTimeUtc = DateTimeOffset.UtcNow };
    }
    public async Task<object> Publish(int year, int month, Guid actor, CancellationToken ct)
    {
        MonthStart(year, month); await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct); await TimesheetGuard.Lock(db, ct);
        var period = await db.TimesheetPeriods.SingleOrDefaultAsync(x => x.Year == year && x.Month == month, ct);
        if (period?.Status == "Closed") throw Closed();
        var sheets = (await Calculate(year, month, null, null, null, ct)).Where(x => x.Lines.Count > 0).ToList();
        if (sheets.Count == 0 || sheets.All(x => x.Lines.Count == 0)) throw new ApiException(409, "EmptyPeriod", "Kỳ này chưa có lịch làm hoặc dữ liệu công.");
        if (period is null) { period = new() { Year = year, Month = month }; db.Add(period); }
        period.Revision++; period.Status = "Published"; period.PublishedAtUtc = DateTimeOffset.UtcNow;
        foreach (var sheet in sheets) db.Add(new TimesheetSnapshot { PeriodId = period.Id, EmployeeId = sheet.EmployeeId,
            Revision = period.Revision, ContentHash = Hash(sheet), DataJson = Serialize(sheet) });
        audit.Add(actor, "TimesheetPeriod", period.Id, "Published", new { period.Revision });
        await db.SaveChangesAsync(ct); await tx.CommitAsync(ct); return new { period.Id, period.Status, period.Revision };
    }
    public async Task<object> Respond(Guid id, Guid employee, string status, string? note, CancellationToken ct)
    {
        await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct); await TimesheetGuard.Lock(db, ct);
        var s = await db.TimesheetSnapshots.Include(x => x.Period).SingleOrDefaultAsync(x => x.Id == id && x.EmployeeId == employee, ct) ?? throw CatalogService.Missing();
        if (s.Period.Status != "Published" || s.Revision != s.Period.Revision) throw new ApiException(409, "StaleVersion", "Phiên bản không còn nhận xác nhận. Hãy tải lại.");
        var current = (await Calculate(s.Period.Year, s.Period.Month, employee, null, null, ct)).SingleOrDefault();
        if (current is null || Hash(current) != s.ContentHash) throw new ApiException(409, "StaleVersion", "Dữ liệu đã thay đổi. Admin cần công bố lại bảng công.");
        if (status is not ("Confirmed" or "Feedback") || status == "Feedback" && string.IsNullOrWhiteSpace(note)) throw new ApiException(400, "InvalidResponse", "Hãy xác nhận hoặc nhập phản hồi.");
        if (s.ResponseStatus != "Pending") throw new ApiException(409, "AlreadyResponded", "Bạn đã phản hồi phiên bản này.");
        s.ResponseStatus = status; s.Feedback = status == "Feedback" ? note!.Trim() : null; s.RespondedAtUtc = DateTimeOffset.UtcNow;
        audit.Add(await db.Employees.Where(x => x.Id == employee).Select(x => x.UserId).SingleAsync(ct), "TimesheetSnapshot", id, status);
        await db.SaveChangesAsync(ct); await tx.CommitAsync(ct); return new { s.ResponseStatus };
    }
    public async Task<object> Resolve(Guid id, string reason, Guid actor, CancellationToken ct)
    {
        RequireReason(reason); await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct); await TimesheetGuard.Lock(db, ct);
        var s = await db.TimesheetSnapshots.Include(x => x.Period).SingleOrDefaultAsync(x => x.Id == id, ct) ?? throw CatalogService.Missing();
        if (s.Period.Status != "Published" || s.Revision != s.Period.Revision || s.ResponseStatus != "Feedback") throw new ApiException(409, "InvalidFeedback", "Phản hồi không còn chờ xử lý.");
        s.ResponseStatus = "Resolved"; s.Resolution = reason.Trim(); s.ResolvedAtUtc = DateTimeOffset.UtcNow; s.ResolvedByUserId = actor;
        audit.Add(actor, "TimesheetSnapshot", id, "FeedbackResolved", new { reason }); await db.SaveChangesAsync(ct); await tx.CommitAsync(ct); return new { s.ResponseStatus };
    }
    public async Task<object> Close(int year, int month, string? reason, Guid actor, CancellationToken ct)
    {
        MonthStart(year, month); await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct); await TimesheetGuard.Lock(db, ct);
        var p = await db.TimesheetPeriods.SingleOrDefaultAsync(x => x.Year == year && x.Month == month, ct) ?? throw CatalogService.Missing();
        if (p.Status != "Published") throw new ApiException(409, "NotPublished", "Cần công bố bảng công trước khi chốt.");
        var sheets = (await Calculate(year, month, null, null, null, ct)).Where(x => x.Lines.Count > 0).ToList();
        var snapshots = await db.TimesheetSnapshots.Where(x => x.PeriodId == p.Id && x.Revision == p.Revision).ToListAsync(ct);
        if (sheets.Count != snapshots.Count || sheets.Any(x => !snapshots.Any(s => s.EmployeeId == x.EmployeeId && s.ContentHash == Hash(x))))
            throw new ApiException(409, "StaleVersion", "Dữ liệu thay đổi sau công bố. Hãy công bố phiên bản mới và cho nhân viên xác nhận lại.");
        var pending = snapshots.Count(x => x.ResponseStatus == "Pending"); var feedback = snapshots.Count(x => x.ResponseStatus == "Feedback");
        var missing = sheets.Sum(x => x.MissingShifts); var conflicts = sheets.Sum(x => x.Lines.Count(l => l.Status == "LeaveConflict"));
        var unfinished = sheets.Sum(x => x.Lines.Count(l => l.Status is "Scheduled" or "Working"));
        if (conflicts > 0) throw new ApiException(409, "LeaveConflict", "Cần xử lý xung đột nghỉ phép/chấm công trước khi chốt.");
        if (pending + feedback + missing + unfinished > 0 && string.IsNullOrWhiteSpace(reason))
            throw new ApiException(409, "UnresolvedPeriod", $"Còn {pending} người chưa xác nhận, {feedback} phản hồi chưa xử lý, {missing} ca thiếu công, {unfinished} ca chưa hoàn tất. Cần xử lý hoặc nhập lý do chốt ngoại lệ.");
        if (!string.IsNullOrWhiteSpace(reason)) RequireReason(reason);
        p.Status = "Closed"; p.ClosedAtUtc = DateTimeOffset.UtcNow; p.ClosedByUserId = actor; p.ExceptionReason = reason?.Trim();
        audit.Add(actor, "TimesheetPeriod", p.Id, "Closed", new { p.Revision, pending, feedback, missing, unfinished, reason });
        await db.SaveChangesAsync(ct); await tx.CommitAsync(ct); return new { p.Status, pending, feedback, missing, unfinished };
    }
    public async Task<object> Reopen(int year, int month, string reason, Guid actor, CancellationToken ct)
    {
        RequireReason(reason); await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct); await TimesheetGuard.Lock(db, ct);
        var p = await db.TimesheetPeriods.SingleOrDefaultAsync(x => x.Year == year && x.Month == month, ct) ?? throw CatalogService.Missing();
        if (p.Status != "Closed") throw new ApiException(409, "NotClosed", "Kỳ chưa được chốt.");
        p.Status = "Draft"; audit.Add(actor, "TimesheetPeriod", p.Id, "Reopened", new { p.Revision, reason });
        await db.SaveChangesAsync(ct); await tx.CommitAsync(ct); return new { p.Status };
    }
    internal static void RequireReason(string? reason) { if (string.IsNullOrWhiteSpace(reason) || reason.Trim().Length < 5 || reason.Length > 1000) throw new ApiException(400, "ReasonRequired", "Lý do cần từ 5 đến 1000 ký tự."); }
    private static ApiException Closed() => new(409, "PeriodClosed", "Kỳ đã chốt. Cần mở lại và ghi lý do.");
}
