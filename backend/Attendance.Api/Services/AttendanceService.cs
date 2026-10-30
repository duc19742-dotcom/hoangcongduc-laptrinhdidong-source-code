using System.Text.Json;
using Attendance.Api.Data;
using Attendance.Api.DTOs;
using Attendance.Api.Entities;
using Attendance.Api.Middleware;
using Microsoft.EntityFrameworkCore;
namespace Attendance.Api.Services;

public sealed class AttendanceService(AttendanceDbContext db,AuditService audit,IConfiguration config)
{
 public async Task<Guid> EmployeeId(Guid user,CancellationToken ct)=>await db.Employees.Where(x=>x.UserId==user&&x.IsActive).Select(x=>(Guid?)x.Id).SingleOrDefaultAsync(ct)??throw new ApiException(403,"NoEmployee","Tài khoản chưa có hồ sơ nhân viên đang hoạt động.");
 public async Task<object> CreateQr(QrCreateDto d,Guid actor,CancellationToken ct)
 {
  Action(d.Action);var shift=await db.Shifts.FindAsync([d.ShiftId],ct)??throw CatalogService.Missing();var location=await db.WorkLocations.FindAsync([d.WorkLocationId],ct)??throw CatalogService.Missing();
  if(!shift.IsActive||!location.IsActive)throw new ApiException(400,"InactiveQrTarget","Ca hoặc địa điểm đã ngừng hoạt động.");
  var token=Secrets.NewToken();var q=new QrSession {TokenHash=Secrets.Hash(token),CreatedByUserId=actor,ShiftId=d.ShiftId,WorkLocationId=d.WorkLocationId,WorkDate=d.WorkDate,Action=d.Action,ExpiresAtUtc=DateTimeOffset.UtcNow.AddSeconds(d.TtlSeconds)};
  db.QrSessions.Add(q);audit.Add(actor,"QrSession",q.Id,"Created",new{q.Action,q.WorkDate,q.ExpiresAtUtc});await db.SaveChangesAsync(ct);
  return new{id=q.Id,qrToken=token,q.ExpiresAtUtc,q.Action};
 }
 private static void Action(string action) {if(action is not("CheckIn" or "CheckOut"))throw new ApiException(400,"InvalidAction","Chỉ hỗ trợ CheckIn hoặc CheckOut.");}
 private async Task<QrSession> ValidateQr(string token,EmployeeShift assignment,string action,DateTimeOffset now,CancellationToken ct)
 {
  Action(action);var hash=Secrets.Hash(token);var qr=await db.QrSessions.FirstOrDefaultAsync(x=>x.TokenHash==hash,ct)??throw new ApiException(400,"InvalidQr","Mã QR không hợp lệ.");
  if(qr.RevokedAtUtc.HasValue||qr.ExpiresAtUtc<=now)throw new ApiException(410,"QrExpired","Mã QR đã hết hạn hoặc bị thu hồi. Hãy yêu cầu mã mới.");
  if(qr.ShiftId!=assignment.ShiftId||qr.WorkLocationId!=assignment.WorkLocationId||qr.WorkDate!=assignment.WorkDate||qr.Action!=action)throw new ApiException(400,"QrMismatch","QR không khớp ca, ngày, địa điểm hoặc thao tác chấm công.");
  return qr;
 }
 public async Task<object> VerifyQr(QrVerifyDto d,Guid user,CancellationToken ct)
 {
  var employee=await EmployeeId(user,ct);var assignment=await db.EmployeeShifts.SingleOrDefaultAsync(x=>x.Id==d.EmployeeShiftId&&x.EmployeeId==employee,ct)??throw CatalogService.Missing();
  var qr=await ValidateQr(d.QrToken,assignment,d.Action,DateTimeOffset.UtcNow,ct);return new{valid=true,qr.ExpiresAtUtc,qr.Action};
 }
 public async Task<object> Submit(AttendanceSubmitDto d,string action,Guid key,Guid user,CancellationToken ct)
 {
  Geo.Validate(d.Latitude,d.Longitude,d.AccuracyMeters);if(key==Guid.Empty)throw new ApiException(400,"MissingIdempotencyKey","Thiếu mã định danh thao tác.");
  var employee=await EmployeeId(user,ct);var payloadHash=Secrets.Hash(action+JsonSerializer.Serialize(d));
  await using var tx=await db.Database.BeginTransactionAsync(ct);await TimesheetGuard.Lock(db,ct);
  var assignment=await db.EmployeeShifts.FromSqlInterpolated($"SELECT * FROM EmployeeShifts WITH (UPDLOCK, ROWLOCK) WHERE Id={d.EmployeeShiftId}").Include(x=>x.WorkLocation).Include(x=>x.Shift).SingleOrDefaultAsync(ct)??throw CatalogService.Missing();
  if(assignment.EmployeeId!=employee)throw CatalogService.Missing();
  var old=await db.AttendanceAttempts.FirstOrDefaultAsync(x=>x.EmployeeId==employee&&x.IdempotencyKey==key,ct);
  if(old is not null){if(!Secrets.Equal(old.PayloadHash,payloadHash))throw new ApiException(409,"IdempotencyMismatch","Mã thao tác đã dùng với dữ liệu khác.");var oldResult=await Result(old,ct);await tx.CommitAsync(ct);return oldResult;}
  var now=DateTimeOffset.UtcNow;
  // A confirmed retry returns above even after GPS/QR expiry. New submissions
  // from updated clients must carry a recent fix, never reuse a cached position.
  if(d.CapturedAtUtc.HasValue&&(d.CapturedAtUtc.Value<now.AddSeconds(-60)||d.CapturedAtUtc.Value>now.AddSeconds(30)))throw new ApiException(400,"StaleGps","GPS đã cũ hoặc giờ điện thoại chưa đúng. Bật ngày giờ tự động và lấy lại GPS trước khi quét QR mới.");
  var early=config.GetValue("Attendance:EarlyCheckInMinutes",120);var late=config.GetValue("Attendance:CheckoutAfterEndMinutes",360);
  if(now<assignment.StartUtc.AddMinutes(-early)||now>(action=="CheckIn"?assignment.EndUtc:assignment.EndUtc.AddMinutes(late)))throw new ApiException(409,"OutsideShiftWindow","Hiện không nằm trong khung giờ chấm công của ca.");
  if(!assignment.Shift.IsActive||!assignment.WorkLocation.IsActive)throw new ApiException(409,"InactiveShift","Ca hoặc địa điểm đã ngừng hoạt động.");
  if(await db.AttendanceRecords.AnyAsync(x=>x.EmployeeShiftId==assignment.Id&&x.Action==action,ct))throw new ApiException(409,"AttendanceAlreadyExists","Bạn đã chấm công thao tác này cho ca.");
  if(action=="CheckOut"&&!await db.AttendanceRecords.AnyAsync(x=>x.EmployeeShiftId==assignment.Id&&x.Action=="CheckIn"&&x.EffectiveAtUtc<=now,ct))throw new ApiException(409,"CheckInRequired","Cần chấm công vào được xác nhận trước khi chấm công ra.");
  var approvedLeave=await db.LeaveRequests.Where(x=>x.EmployeeId==employee&&x.Status=="Approved"&&x.FromDate<=assignment.WorkDate&&x.ToDate>=assignment.WorkDate).ToListAsync(ct);
  if(approvedLeave.Any(x=>x.Kind=="FullDay"||x.FromUtc<=now&&x.ToUtc>now))throw new ApiException(409,"ApprovedLeave","Bạn đang trong khoảng nghỉ phép đã duyệt. Nếu đi làm thay đổi kế hoạch, hãy nhờ Admin thu hồi phép có lý do trước khi chấm công.");
  QrSession? qr=null;
  if(string.IsNullOrWhiteSpace(d.QrToken))throw new ApiException(400,"QrRequired","Hãy quét mã QR tại công ty.");
  if(d.QrToken.StartsWith("site_")) {
   var hash=Secrets.Hash(d.QrToken);var site=await db.Set<SiteQrSession>().SingleOrDefaultAsync(x=>x.TokenHash==hash,ct)??throw new ApiException(400,"InvalidQr","Mã QR công ty không hợp lệ.");
   if(site.ExpiresAtUtc<=now||site.RevokedAtUtc.HasValue)throw new ApiException(410,"QrExpired","QR đã hết hạn. Hãy quét mã mới trên màn hình công ty.");
   if(site.WorkLocationId!=assignment.WorkLocationId)throw new ApiException(400,"QrMismatch","QR không thuộc địa điểm của ca này.");
  } else qr=await ValidateQr(d.QrToken,assignment,action,now,ct);
  if(qr is not null&&await db.QrRedemptions.AnyAsync(x=>x.QrSessionId==qr.Id&&x.EmployeeId==employee,ct))throw new ApiException(409,"QrAlreadyUsed","Bạn đã dùng phiên QR này. Xem kết quả trước đó hoặc yêu cầu QR mới.");
  var location=assignment.WorkLocation;var distance=Geo.Distance(d.Latitude,d.Longitude,location.Latitude,location.Longitude);var reasons=new List<string>();
  if(distance>location.RadiusMeters)reasons.Add("OutsideGeofence");if(d.AccuracyMeters>location.MaxAccuracyMeters)reasons.Add("LowGpsAccuracy");
  var a=new AttendanceAttempt {EmployeeId=employee,EmployeeShiftId=assignment.Id,QrSessionId=qr?.Id,Action=action,ReceivedAtUtc=now,Latitude=d.Latitude,Longitude=d.Longitude,AccuracyMeters=d.AccuracyMeters,DistanceMeters=distance,
   Outcome=reasons.Count==0?"Accepted":"NeedsReview",ReasonCode=string.Join(',',reasons),IdempotencyKey=key,PayloadHash=payloadHash,
   PolicySnapshotJson=JsonSerializer.Serialize(new{locationName=location.Name,latitude=location.Latitude,longitude=location.Longitude,radiusMeters=location.RadiusMeters,maxAccuracyMeters=location.MaxAccuracyMeters,policyVersion=location.PolicyVersion})};
  db.AttendanceAttempts.Add(a);if(qr is not null)db.QrRedemptions.Add(new QrRedemption {QrSessionId=qr.Id,EmployeeId=employee,AttemptId=a.Id});
  if(a.Outcome=="Accepted")db.AttendanceRecords.Add(new AttendanceRecord {EmployeeShiftId=assignment.Id,AttemptId=a.Id,Action=action,EffectiveAtUtc=now,RecordedAtUtc=now});
  audit.Add(user,"AttendanceAttempt",a.Id,a.Outcome,new{a.EmployeeShiftId,a.Action,a.ReasonCode});await db.SaveChangesAsync(ct);var result=await Result(a,ct);await tx.CommitAsync(ct);return result;
 }
 public async Task<object> Result(AttendanceAttempt a,CancellationToken ct)
 {
  var record=await db.AttendanceRecords.Where(x=>x.AttemptId==a.Id).Select(x=>new{x.Id,x.Action,x.EffectiveAtUtc,x.RecordedAtUtc,x.Source}).FirstOrDefaultAsync(ct);
  var schedule=await db.EmployeeShifts.SingleAsync(x=>x.Id==a.EmployeeShiftId,ct);
  var leaves=await db.LeaveRequests.AsNoTracking().Where(x=>x.EmployeeId==schedule.EmployeeId&&x.Status=="Approved"&&x.FromDate<=schedule.WorkDate&&x.ToDate>=schedule.WorkDate).ToListAsync(ct);
  var (expectedStart,expectedEnd)=LeaveService.ExpectedWindow(schedule.StartUtc,schedule.EndUtc,leaves.Select(x=>(x.Kind=="FullDay"?schedule.StartUtc:x.FromUtc!.Value,x.Kind=="FullDay"?schedule.EndUtc:x.ToUtc!.Value)));
  var lateMinutes=a.Action=="CheckIn"&&a.ReceivedAtUtc>expectedStart.AddMinutes(schedule.GraceMinutesSnapshot)?Math.Max(0,(a.ReceivedAtUtc-expectedStart).TotalMinutes):0;
  var punctuality=a.Action=="CheckIn"?(a.ReceivedAtUtc>expectedStart.AddMinutes(schedule.GraceMinutesSnapshot)?"Late":"OnTime"):(a.ReceivedAtUtc<expectedEnd?"EarlyLeave":"Completed");
  var hasRequest=await db.AttendanceRequests.AnyAsync(x=>x.AttemptId==a.Id,ct);
  return new{attemptId=a.Id,status=a.Outcome,punctuality,lateMinutes=Math.Ceiling(lateMinutes),scheduledStartUtc=schedule.StartUtc,scheduledEndUtc=schedule.EndUtc,graceMinutes=schedule.GraceMinutesSnapshot,reasonCodes=a.ReasonCode.Split(',',StringSplitOptions.RemoveEmptyEntries),a.ReceivedAtUtc,a.DistanceMeters,a.AccuracyMeters,position=new{latitude=a.Latitude,longitude=a.Longitude,accuracyMeters=a.AccuracyMeters},policy=JsonSerializer.Deserialize<JsonElement>(a.PolicySnapshotJson),canCreateRequest=a.Outcome=="NeedsReview"&&!hasRequest,attendanceRecord=record};
 }
 public Task<object> History(Guid? employee,DateOnly? from,DateOnly? to,int page,int size,CancellationToken ct)
 {
  var range=Paging.Dates(from,to);var q=db.AttendanceRecords.Where(x=>x.EffectiveAtUtc>=range.Start&&x.EffectiveAtUtc<range.End);if(employee.HasValue)q=q.Where(x=>x.EmployeeShift.EmployeeId==employee);
  return Paging.Page(q.OrderByDescending(x=>x.EffectiveAtUtc).Select(x=>new{x.Id,x.Action,x.EffectiveAtUtc,x.RecordedAtUtc,x.Source,x.EmployeeShiftId,employeeName=x.EmployeeShift.Employee.FullName,employeeCode=x.EmployeeShift.Employee.EmployeeCode,shiftName=x.EmployeeShift.Shift.Name,x.EmployeeShift.WorkDate,x.AttemptId,distanceMeters=(double?)x.Attempt.DistanceMeters,accuracyMeters=(double?)x.Attempt.AccuracyMeters}),page,size,ct);
 }
 public async Task<object> Statistics(DateOnly? from,DateOnly? to,Guid? department,CancellationToken ct)
 {
  var range=Paging.Dates(from,to);var q=db.AttendanceRecords.Where(x=>x.EffectiveAtUtc>=range.Start&&x.EffectiveAtUtc<range.End);if(department.HasValue)q=q.Where(x=>x.EmployeeShift.Employee.DepartmentId==department);
  var rows=await q.Select(x=>new{x.EmployeeShiftId,x.Action,x.EffectiveAtUtc,x.EmployeeShift.StartUtc,x.EmployeeShift.EndUtc,x.EmployeeShift.EmployeeId,x.EmployeeShift.WorkDate,x.EmployeeShift.GraceMinutesSnapshot}).ToListAsync(ct);
  var groups=rows.GroupBy(x=>x.EmployeeShiftId).ToList();var minutes=0d;var open=0;var lateCount=0;
  var employeeIds=rows.Select(x=>x.EmployeeId).Distinct().ToList();
  var leaves=await db.LeaveRequests.AsNoTracking().Where(x=>employeeIds.Contains(x.EmployeeId)&&x.Status=="Approved").ToListAsync(ct);
  foreach(var group in groups){var first=group.First();var applicable=leaves.Where(x=>x.EmployeeId==first.EmployeeId&&x.FromDate<=first.WorkDate&&x.ToDate>=first.WorkDate);var (expectedStart,_)=LeaveService.ExpectedWindow(first.StartUtc,first.EndUtc,applicable.Select(x=>(x.Kind=="FullDay"?first.StartUtc:x.FromUtc!.Value,x.Kind=="FullDay"?first.EndUtc:x.ToUtc!.Value)));lateCount+=group.Count(x=>x.Action=="CheckIn"&&x.EffectiveAtUtc>expectedStart.AddMinutes(x.GraceMinutesSnapshot));var i=group.FirstOrDefault(x=>x.Action=="CheckIn");var o=group.FirstOrDefault(x=>x.Action=="CheckOut");if(i is not null&&o is not null)minutes+=Math.Max(0,(o.EffectiveAtUtc-i.EffectiveAtUtc).TotalMinutes);else if(i is not null)open++;}
  return new{checkIns=rows.Count(x=>x.Action=="CheckIn"),checkOuts=rows.Count(x=>x.Action=="CheckOut"),lateCheckIns=lateCount,openShifts=open,confirmedHours=Math.Round(minutes/60,2),daily=rows.GroupBy(x=>x.WorkDate).OrderBy(x=>x.Key).Select(x=>new{date=x.Key,count=x.Count()})};
 }
}

