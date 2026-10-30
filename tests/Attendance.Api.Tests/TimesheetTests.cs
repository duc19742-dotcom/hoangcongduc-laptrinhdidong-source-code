using System.IO.Compression;
using System.Net;
using System.Net.Http.Headers;
using System.Xml.Linq;
using Attendance.Api.Controllers;
using Attendance.Api.Data;
using Attendance.Api.Entities;
using Attendance.Api.Middleware;
using Attendance.Api.Services;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace Attendance.Api.Tests;

public sealed partial class IntegrationTests
{
    private static void Move(EmployeeShift a, DateOnly day, int start = 8, int end = 17, bool overnight = false)
    {
        a.WorkDate = day; a.StartUtc = Geo.Utc(day, new(start, 0)); a.EndUtc = Geo.Utc(day.AddDays(overnight ? 1 : 0), new(end, 0));
    }
    private static AttendanceRecord Record(EmployeeShift a, string action, DateTimeOffset at) => new() { EmployeeShiftId = a.Id,
        Action = action, EffectiveAtUtc = at, RecordedAtUtc = at, Source = "AdminCorrection" };

    [Fact] public async Task MonthlyLedger_MultipleAndOvernightShifts_MissingOutIsUnknown_NotZero()
    {
        using var scope = fixture.Factory.Services.CreateScope(); var s = await Seed(scope.ServiceProvider);
        var db = scope.ServiceProvider.GetRequiredService<AttendanceDbContext>(); var service = scope.ServiceProvider.GetRequiredService<TimesheetService>();
        var day = new DateOnly(2010, 2, 28); Move(s.Assignment, day, 20, 4, true);
        db.Add(Record(s.Assignment, "CheckIn", s.Assignment.StartUtc.AddMinutes(10))); db.Add(Record(s.Assignment, "CheckOut", s.Assignment.EndUtc.AddMinutes(-15)));
        var shift = new Shift { Code = Guid.NewGuid().ToString("N"), Name = "Second shift", StartLocalTime = new(10, 0), EndLocalTime = new(12, 0) };
        var other = new EmployeeShift { EmployeeId = s.Employee.Id, Shift = shift, WorkLocationId = s.Assignment.WorkLocationId }; Move(other, day, 10, 12); db.Add(other);
        db.Add(Record(other, "CheckIn", other.StartUtc)); await db.SaveChangesAsync();
        var sheet = Assert.Single(await service.Calculate(2010, 2, s.Employee.Id, null, null, default));
        Assert.Equal(2, sheet.ScheduledShifts); Assert.Equal(1, sheet.ScheduledDays); Assert.Equal(1, sheet.AttendedDays);
        Assert.Equal(7.58, sheet.ConfirmedHours); Assert.Equal(1, sheet.MissingShifts);
        var night = sheet.Lines.Single(x => x.AssignmentId == s.Assignment.Id); Assert.Equal(10, night.LateMinutes); Assert.Equal(15, night.EarlyMinutes);
        var open = sheet.Lines.Single(x => x.AssignmentId == other.Id); Assert.Null(open.WorkedMinutes); Assert.Equal("MissingCheckOut", open.Status);
        Assert.All(sheet.Lines, x => Assert.Equal(day, x.Date));
    }

    [Fact] public async Task RecurringSchedules_AppearWithoutPhoneLogin_AndNoScheduleIsNotAbsence()
    {
        using var scope = fixture.Factory.Services.CreateScope(); var s = await Seed(scope.ServiceProvider);
        var db = scope.ServiceProvider.GetRequiredService<AttendanceDbContext>(); var service = scope.ServiceProvider.GetRequiredService<TimesheetService>();
        s.Employee.HireDate = new(2012, 1, 1);
        db.Add(new WorkSchedule { EmployeeId = s.Employee.Id, ShiftId = s.Assignment.ShiftId, WorkLocationId = s.Assignment.WorkLocationId,
            FromDate = new(2012, 1, 2), ToDate = new(2012, 1, 2), WeekdaysMask = 127 }); await db.SaveChangesAsync();
        var sheet = Assert.Single(await service.Calculate(2012, 1, s.Employee.Id, null, null, default));
        Assert.Single(sheet.Lines); Assert.Equal(new DateOnly(2012, 1, 2), sheet.Lines[0].Date); Assert.Equal("MissingCheckIn", sheet.Lines[0].Status);
        Assert.False(await db.EmployeeShifts.AnyAsync(x => x.EmployeeId == s.Employee.Id && x.WorkDate.Year == 2012));
    }

    [Fact] public async Task Leave_HalfOfSixHourShiftIsThreeHours_AndDuplicateIsRejected()
    {
        using var scope = fixture.Factory.Services.CreateScope(); var s = await Seed(scope.ServiceProvider);
        var db = scope.ServiceProvider.GetRequiredService<AttendanceDbContext>(); var leave = scope.ServiceProvider.GetRequiredService<LeaveService>();
        var service = scope.ServiceProvider.GetRequiredService<TimesheetService>(); var day = new DateOnly(2013, 3, 10); Move(s.Assignment, day, 8, 14); await db.SaveChangesAsync();
        var dto = new LeaveDto(day, day, "HalfDay", "Test half day leave", s.Assignment.StartUtc, "First");
        var result = Json(await leave.Save(null, s.Employee.Id, dto, s.User.Id, default)); var id = result.GetProperty("Id").GetGuid();
        await leave.Decide(id, null, "Approved", "Approved test leave", s.Admin.Id, default);
        var sheet = Assert.Single(await service.Calculate(2013, 3, s.Employee.Id, null, null, default)); Assert.Equal(3, sheet.LeaveHours); Assert.Equal(180, Assert.Single(sheet.Lines).LeaveMinutes);
        Assert.Equal("LeaveOverlap", (await Assert.ThrowsAsync<ApiException>(() => leave.Save(null, s.Employee.Id, dto, s.User.Id, default))).Code);
        db.ChangeTracker.Clear();
        Assert.Equal("LeaveReviewed", (await Assert.ThrowsAsync<ApiException>(() => leave.Save(id, s.Employee.Id, dto, s.User.Id, default))).Code);
    }

    [Fact] public async Task Leave_FullDayIsNotAbsence_ApprovalCannotOverwriteActualAttendance()
    {
        using var scope = fixture.Factory.Services.CreateScope(); var s = await Seed(scope.ServiceProvider);
        var db = scope.ServiceProvider.GetRequiredService<AttendanceDbContext>(); var leave = scope.ServiceProvider.GetRequiredService<LeaveService>(); var service = scope.ServiceProvider.GetRequiredService<TimesheetService>();
        var day = new DateOnly(2014, 4, 10); Move(s.Assignment, day); await db.SaveChangesAsync();
        var result = Json(await leave.Save(null, s.Employee.Id, new(day, day, "FullDay", "Test full leave"), s.User.Id, default)); var id = result.GetProperty("Id").GetGuid();
        db.Add(Record(s.Assignment, "CheckIn", s.Assignment.StartUtc)); await db.SaveChangesAsync();
        Assert.Equal("AttendanceConflict", (await Assert.ThrowsAsync<ApiException>(() => leave.Decide(id, null, "Approved", "Review for overlap", s.Admin.Id, default))).Code);
        Assert.Single(await db.AttendanceRecords.Where(x => x.EmployeeShiftId == s.Assignment.Id).ToListAsync());
        db.RemoveRange(await db.AttendanceRecords.Where(x => x.EmployeeShiftId == s.Assignment.Id).ToListAsync()); await db.SaveChangesAsync();
        await leave.Decide(id, null, "Approved", "Approved without attendance", s.Admin.Id, default);
        var sheet = Assert.Single(await service.Calculate(2014, 4, s.Employee.Id, null, null, default)); Assert.Equal("Leave", Assert.Single(sheet.Lines).Status); Assert.Equal(0, sheet.MissingShifts); Assert.Equal(9, sheet.LeaveHours);
    }

    [Fact] public async Task PublishedLedger_ResponseBoundToVersion_ClosedPeriodGuardsLegacyWrites_AndReopenRetainsHistory()
    {
        using var scope = fixture.Factory.Services.CreateScope(); var s = await Seed(scope.ServiceProvider);
        var db = scope.ServiceProvider.GetRequiredService<AttendanceDbContext>(); var service = scope.ServiceProvider.GetRequiredService<TimesheetService>();
        Move(s.Assignment, new(2015, 5, 10)); db.Add(Record(s.Assignment, "CheckIn", s.Assignment.StartUtc)); db.Add(Record(s.Assignment, "CheckOut", s.Assignment.EndUtc)); await db.SaveChangesAsync();
        await service.Publish(2015, 5, s.Admin.Id, default);
        var snapshot = await db.TimesheetSnapshots.Include(x => x.Period).SingleAsync(x => x.EmployeeId == s.Employee.Id && x.Period.Year == 2015);
        await Assert.ThrowsAsync<ApiException>(() => service.Respond(snapshot.Id, Guid.NewGuid(), "Confirmed", null, default));
        s.Assignment.GraceMinutesSnapshot = 7; await db.SaveChangesAsync();
        Assert.Equal("StaleVersion", (await Assert.ThrowsAsync<ApiException>(() => service.Respond(snapshot.Id, s.Employee.Id, "Confirmed", null, default))).Code);
        await service.Publish(2015, 5, s.Admin.Id, default);
        var latest = await db.TimesheetSnapshots.SingleAsync(x => x.EmployeeId == s.Employee.Id && x.PeriodId == snapshot.PeriodId && x.Revision == 2);
        await service.Respond(latest.Id, s.Employee.Id, "Confirmed", null, default);
        await service.Close(2015, 5, "Test close with unrelated employees unconfirmed", s.Admin.Id, default);
        var saved = latest.DataJson;
        s.Assignment.GraceMinutesSnapshot = 10;
        Assert.Equal("PeriodClosed", (await Assert.ThrowsAsync<ApiException>(() => db.SaveChangesAsync())).Code);
        db.Entry(s.Assignment).State = EntityState.Unchanged;
        var record = await db.AttendanceRecords.FirstAsync(x => x.EmployeeShiftId == s.Assignment.Id); db.Remove(record);
        Assert.Equal("PeriodClosed", (await Assert.ThrowsAsync<ApiException>(() => db.SaveChangesAsync())).Code); db.Entry(record).State = EntityState.Unchanged;
        Assert.Equal(saved, (await db.TimesheetSnapshots.AsNoTracking().SingleAsync(x => x.Id == latest.Id)).DataJson);
        await service.Reopen(2015, 5, "Test reopen for correction", s.Admin.Id, default);
        Assert.Equal(2, await db.TimesheetSnapshots.CountAsync(x => x.EmployeeId == s.Employee.Id && x.PeriodId == snapshot.PeriodId));
        s.Assignment.GraceMinutesSnapshot = 9; await db.SaveChangesAsync();
        Assert.True(await db.AuditLogs.AnyAsync(x => x.EntityId == snapshot.PeriodId && x.Action == "Reopened"));
    }

    [Fact] public async Task CloseRequiresExplicitException_WhenMissingAttendanceOrConfirmation()
    {
        using var scope = fixture.Factory.Services.CreateScope(); var s = await Seed(scope.ServiceProvider);
        var db = scope.ServiceProvider.GetRequiredService<AttendanceDbContext>(); var service = scope.ServiceProvider.GetRequiredService<TimesheetService>();
        Move(s.Assignment, new(2016, 6, 10)); await db.SaveChangesAsync(); await service.Publish(2016, 6, s.Admin.Id, default);
        Assert.Equal("UnresolvedPeriod", (await Assert.ThrowsAsync<ApiException>(() => service.Close(2016, 6, null, s.Admin.Id, default))).Code);
        await service.Close(2016, 6, "Explicit exception in isolated test", s.Admin.Id, default);
        Assert.Equal("Closed", (await db.TimesheetPeriods.SingleAsync(x => x.Year == 2016 && x.Month == 6)).Status);
        await service.Reopen(2016, 6, "Leave test database editable", s.Admin.Id, default);
    }

    [Fact] public async Task Http_TimesheetOwnershipAndExportAndPublishAreEnforced()
    {
        using var scope = fixture.Factory.Services.CreateScope(); var s = await Seed(scope.ServiceProvider);
        var auth = scope.ServiceProvider.GetRequiredService<AuthService>(); var code = await EmailCode(auth, await auth.Login(new(s.User.UserName, Password), default));
        var result = Json(await auth.Verify(new(code.Flow.FlowId, code.Flow.FlowToken, code.Challenge, code.Code), "Login", default));
        using var client = fixture.Factory.CreateClient(new() { BaseAddress = new("https://localhost") }); client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", result.GetProperty("accessToken").GetString());
        var response = await client.GetAsync($"/api/v1/timesheets/{s.Assignment.WorkDate.Year}/{s.Assignment.WorkDate.Month}?employeeId={Guid.NewGuid()}"); Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = System.Text.Json.JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.All(body.RootElement.GetProperty("items").EnumerateArray(), x => Assert.Equal(s.Employee.Id, x.GetProperty("data").GetProperty("employeeId").GetGuid()));
        Assert.Equal(HttpStatusCode.Forbidden, (await client.GetAsync("/api/v1/timesheets/2017/1/export")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await client.PostAsync("/api/v1/timesheets/2017/1/publish", null)).StatusCode);
    }

    [Fact] public void Workbook_IsTypedOpenXml_AndUntrustedTextNeverBecomesFormula()
    {
        var data = new EmployeeTimesheet(Guid.NewGuid(), "=1+1", "Đức nhân viên", Guid.NewGuid(), "Phòng kế toán", 2026, 10, []);
        var bytes = TimesheetExport.Create([data], "Nháp", 1, "Tất cả");
        using var zip = new ZipArchive(new MemoryStream(bytes)); Assert.NotNull(zip.GetEntry("[Content_Types].xml"));
        using var input = zip.GetEntry("xl/worksheets/sheet1.xml")!.Open(); var xml = XDocument.Load(input); XNamespace ns = "http://schemas.openxmlformats.org/spreadsheetml/2006/main";
        Assert.Empty(xml.Descendants(ns + "f")); Assert.Contains(xml.Descendants(ns + "t"), x => x.Value == "=1+1"); Assert.Contains(xml.Descendants(ns + "t"), x => x.Value == "Đức nhân viên");
        Assert.Contains(xml.Descendants(ns + "c"), x => (string?)x.Attribute("s") == "1" && x.Element(ns + "v") != null);
    }

    [Fact] public async Task ConcurrentClose_OnlyOneTransitionSucceeds()
    {
        using var setup = fixture.Factory.Services.CreateScope(); var s = await Seed(setup.ServiceProvider);
        var db = setup.ServiceProvider.GetRequiredService<AttendanceDbContext>(); Move(s.Assignment, new(2019, 9, 10)); await db.SaveChangesAsync();
        await setup.ServiceProvider.GetRequiredService<TimesheetService>().Publish(2019, 9, s.Admin.Id, default);
        async Task<string> Close()
        {
            using var scope = fixture.Factory.Services.CreateScope();
            try { await scope.ServiceProvider.GetRequiredService<TimesheetService>().Close(2019, 9, "Concurrent test explicit exception", s.Admin.Id, default); return "Closed"; }
            catch (ApiException e) { return e.Code; }
        }
        var results = await Task.WhenAll(Close(), Close()); Assert.Single(results, x => x == "Closed"); Assert.Single(results, x => x == "NotPublished");
        using var cleanup = fixture.Factory.Services.CreateScope();
        await cleanup.ServiceProvider.GetRequiredService<TimesheetService>().Reopen(2019, 9, "Restore isolated test period", s.Admin.Id, default);
    }

    [Fact] public async Task Dashboard_DoesNotMarkFutureShiftsAsMissing_AndRespectsDepartment()
    {
        using var scope = fixture.Factory.Services.CreateScope(); var s = await Seed(scope.ServiceProvider);
        var db = scope.ServiceProvider.GetRequiredService<AttendanceDbContext>(); var date = new DateOnly(2090, 10, 10); Move(s.Assignment, date); await db.SaveChangesAsync();
        var c = Controller(new DashboardController(scope.ServiceProvider.GetRequiredService<TimesheetService>(), db), s.Admin.Id, "Admin");
        var result = Json(await c.Get(date, s.Employee.DepartmentId, default)); Assert.Equal(1, result.GetProperty("scheduled").GetInt32()); Assert.Equal(0, result.GetProperty("missingIn").GetInt32());
        Assert.Single(result.GetProperty("items").EnumerateArray());
        Assert.Equal(0, Json(await c.Get(date, Guid.NewGuid(), default)).GetProperty("scheduled").GetInt32());
    }
}
