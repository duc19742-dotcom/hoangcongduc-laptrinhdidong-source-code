using Attendance.Api.Data;
using Attendance.Api.Entities;
using Attendance.Api.Middleware;
using Microsoft.EntityFrameworkCore;

namespace Attendance.Api.Services;

// One transaction-owned SQL application lock serializes ledger publication with
// writes from both new and legacy endpoints, across API processes.
public static class TimesheetGuard
{
    public static bool HasRelevantChanges(AttendanceDbContext db) => db.ChangeTracker.Entries().Any(e =>
        e.State is EntityState.Added or EntityState.Modified or EntityState.Deleted &&
        e.Entity is EmployeeShift or AttendanceRecord or LeaveRequest or WorkSchedule or TimesheetPeriod or TimesheetSnapshot);

    public static Task Lock(AttendanceDbContext db, CancellationToken ct) => db.Database.ExecuteSqlRawAsync("""
        DECLARE @result int;
        EXEC @result = sys.sp_getapplock @Resource = N'DucAttendance.Timesheets',
             @LockMode = N'Exclusive', @LockOwner = N'Transaction', @LockTimeout = 10000;
        IF @result < 0 THROW 51001, 'Timesheet operation is busy. Retry later.', 1;
        """, ct);

    public static async Task Validate(AttendanceDbContext db, CancellationToken ct)
    {
        var closed = await db.TimesheetPeriods.AsNoTracking().Where(x => x.Status == "Closed")
            .Select(x => new { x.Year, x.Month }).ToListAsync(ct);
        if (closed.Count == 0) return;
        void Check(DateOnly from, DateOnly to)
        {
            if (closed.Any(x => new DateOnly(x.Year, x.Month, 1) <= to &&
                new DateOnly(x.Year, x.Month, 1).AddMonths(1).AddDays(-1) >= from))
                throw new ApiException(409, "PeriodClosed", "Kỳ công đã chốt. Admin cần mở lại kỳ và ghi lý do trước khi thay đổi.");
        }
        foreach (var e in db.ChangeTracker.Entries<EmployeeShift>().Where(x => x.State is EntityState.Added or EntityState.Modified or EntityState.Deleted))
        {
            Check(e.Entity.WorkDate, e.Entity.WorkDate);
            if (e.State != EntityState.Added) { var old = e.OriginalValues.GetValue<DateOnly>("WorkDate"); Check(old, old); }
        }
        foreach (var e in db.ChangeTracker.Entries<WorkSchedule>().Where(x => x.State is EntityState.Added or EntityState.Modified or EntityState.Deleted))
        {
            Check(e.Entity.FromDate, e.Entity.ToDate);
            if (e.State != EntityState.Added) Check(e.OriginalValues.GetValue<DateOnly>("FromDate"), e.OriginalValues.GetValue<DateOnly>("ToDate"));
        }
        foreach (var e in db.ChangeTracker.Entries<LeaveRequest>().Where(x => x.State is EntityState.Added or EntityState.Modified or EntityState.Deleted))
        {
            Check(e.Entity.FromDate, e.Entity.ToDate);
            if (e.State != EntityState.Added) Check(e.OriginalValues.GetValue<DateOnly>("FromDate"), e.OriginalValues.GetValue<DateOnly>("ToDate"));
        }
        var ids = db.ChangeTracker.Entries<AttendanceRecord>().Where(x => x.State is EntityState.Added or EntityState.Modified or EntityState.Deleted)
            .SelectMany(x => x.State == EntityState.Added ? new[] { x.Entity.EmployeeShiftId } :
                new[] { x.Entity.EmployeeShiftId, x.OriginalValues.GetValue<Guid>("EmployeeShiftId") }).Distinct().ToList();
        foreach (var day in await db.EmployeeShifts.Where(x => ids.Contains(x.Id)).Select(x => x.WorkDate).ToListAsync(ct)) Check(day, day);
    }
}
