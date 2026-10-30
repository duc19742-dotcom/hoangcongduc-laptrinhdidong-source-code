using System.Data;
using Attendance.Api.Data;
using Attendance.Api.DTOs;
using Attendance.Api.Entities;
using Attendance.Api.Middleware;
using Attendance.Api.Repositories;
using Microsoft.EntityFrameworkCore;
namespace Attendance.Api.Services;

public sealed class CatalogService(AttendanceDbContext db,IRepository<Department> departments,IRepository<Employee> employees,
    IRepository<Shift> shifts,IRepository<WorkLocation> locations,AuditService audit)
{
    public IQueryable<object> EmployeeViews()=>employees.Query().Select(x=>(object)new {
        x.Id,x.EmployeeCode,x.FullName,email=x.User!=null?x.User.Email:x.InvitationEmail,phone=x.User!=null?x.User.PhoneNumber:x.InvitationPhone,
        x.DepartmentId,departmentName=x.Department.Name,x.JobTitle,x.HireDate,x.IsActive,x.UserId,rowVersion=x.RowVersion
    });
    public async Task<object> ListEmployees(string? search,Guid? departmentId,bool? active,int page,int pageSize,CancellationToken ct)
    {
        var q=employees.Query(); if(!string.IsNullOrWhiteSpace(search)){var term=search.Trim();q=q.Where(x=>x.EmployeeCode.Contains(term)||x.FullName.Contains(term));}
        if(departmentId.HasValue)q=q.Where(x=>x.DepartmentId==departmentId);if(active.HasValue)q=q.Where(x=>x.IsActive==active);
        return await Paging.Page(q.OrderBy(x=>x.EmployeeCode).Select(x=>new {x.Id,x.EmployeeCode,x.FullName,email=x.User!=null?x.User.Email:x.InvitationEmail,phone=x.User!=null?x.User.PhoneNumber:x.InvitationPhone,x.DepartmentId,departmentName=x.Department.Name,x.JobTitle,x.HireDate,x.IsActive,x.UserId,rowVersion=x.RowVersion}),page,pageSize,ct);
    }
    public async Task<object> EmployeeView(Guid id,CancellationToken ct)
    {
        var x=await employees.Query().Include(x=>x.Department).Include(x=>x.User).FirstOrDefaultAsync(x=>x.Id==id,ct)??throw Missing();
        return new {x.Id,x.EmployeeCode,x.FullName,email=x.User?.Email??x.InvitationEmail,phone=x.User?.PhoneNumber??x.InvitationPhone,x.DepartmentId,departmentName=x.Department.Name,x.JobTitle,x.HireDate,x.IsActive,x.UserId,rowVersion=x.RowVersion};
    }
    public async Task<object> SaveEmployee(Guid? id,EmployeeDto dto,Guid actor,CancellationToken ct)
    {
        if(!await departments.Query().AnyAsync(x=>x.Id==dto.DepartmentId,ct))throw new ApiException(400,"InvalidDepartment","Phòng ban không tồn tại.");
        var x=id.HasValue?await employees.FindAsync(id.Value,ct)??throw Missing():new Employee();
        if(id.HasValue)Secrets.Version(db,x,dto.RowVersion);else employees.Add(x);
        var phone=Secrets.Phone(dto.Phone);var email=dto.Email.Trim();
        if(x.UserId.HasValue)
        {
            var u=await db.Users.SingleAsync(u=>u.Id==x.UserId,ct);
            if(Secrets.Normalize(email)!=u.NormalizedEmail||phone!=u.PhoneNumber)throw new ApiException(400,"VerifiedContactChange","Không sửa liên hệ đã xác minh qua form nhân viên. Cần quy trình xác minh lại.");
            if(!dto.IsActive){u.IsActive=false;await Revoke(u.Id,ct);}
        }
        x.EmployeeCode=dto.EmployeeCode.Trim().ToUpperInvariant();x.FullName=dto.FullName.Trim();x.InvitationEmail=email;x.InvitationPhone=phone;
        x.DepartmentId=dto.DepartmentId;x.JobTitle=dto.JobTitle.Trim();x.HireDate=dto.HireDate;x.IsActive=dto.IsActive;
        audit.Add(actor,"Employee",x.Id,id.HasValue?"Updated":"Created",new{x.EmployeeCode,x.DepartmentId});await db.SaveChangesAsync(ct);return await EmployeeView(x.Id,ct);
    }
    public async Task Status(Guid id,EmployeeStatusDto dto,Guid actor,CancellationToken ct)
    {
        var x=await employees.Query().Include(x=>x.User).FirstOrDefaultAsync(x=>x.Id==id,ct)??throw Missing();x.IsActive=dto.IsActive;
        if(x.User is not null){x.User.IsActive=dto.IsActive;if(!dto.IsActive)await Revoke(x.User.Id,ct);}
        audit.Add(actor,"Employee",id,"StatusChanged",new{dto.IsActive,dto.Reason});await db.SaveChangesAsync(ct);
    }
    private Task<int> Revoke(Guid user,CancellationToken ct)=>db.AuthSessions.Where(x=>x.UserId==user&&!x.RevokedAtUtc.HasValue).ExecuteUpdateAsync(s=>s.SetProperty(x=>x.RevokedAtUtc,(DateTimeOffset?)DateTimeOffset.UtcNow),ct);
    public async Task DeleteEmployee(Guid id,Guid actor,CancellationToken ct)
    {
        var x=await employees.FindAsync(id,ct)??throw Missing();if(x.UserId.HasValue||await db.EmployeeShifts.AnyAsync(a=>a.EmployeeId==id,ct))throw new ApiException(409,"EmployeeHasHistory","Nhân viên đã liên kết tài khoản hoặc có lịch sử. Hãy ngừng hoạt động.");
        employees.Remove(x);audit.Add(actor,"Employee",id,"Deleted");await db.SaveChangesAsync(ct);
    }
    public Task<object> Departments(int page,int size,CancellationToken ct)=>Paging.Page(departments.Query().OrderBy(x=>x.Code).Select(x=>new{x.Id,x.Code,x.Name,rowVersion=x.RowVersion}),page,size,ct);
    public async Task<object> SaveDepartment(Guid? id,DepartmentDto dto,Guid actor,CancellationToken ct)
    {
        var x=id.HasValue?await departments.FindAsync(id.Value,ct)??throw Missing():new Department();if(id.HasValue)Secrets.Version(db,x,dto.RowVersion);else departments.Add(x);
        x.Code=dto.Code.Trim().ToUpperInvariant();x.Name=dto.Name.Trim();audit.Add(actor,"Department",x.Id,id.HasValue?"Updated":"Created",new{x.Code,x.Name});await db.SaveChangesAsync(ct);return new{x.Id,x.Code,x.Name,rowVersion=x.RowVersion};
    }
    public async Task DeleteDepartment(Guid id,Guid actor,CancellationToken ct)
    {
        var x=await departments.FindAsync(id,ct)??throw Missing();if(await employees.Query().AnyAsync(e=>e.DepartmentId==id,ct))throw new ApiException(409,"DepartmentInUse","Phòng ban vẫn có nhân viên.");departments.Remove(x);audit.Add(actor,"Department",id,"Deleted");await db.SaveChangesAsync(ct);
    }
    public Task<object> Shifts(int page,int size,CancellationToken ct)=>Paging.Page(shifts.Query().OrderBy(x=>x.Code).Select(x=>new{x.Id,x.Code,x.Name,x.StartLocalTime,x.EndLocalTime,x.EndsNextDay,x.LateGraceMinutes,x.IsActive,rowVersion=x.RowVersion}),page,size,ct);
    public async Task<object> SaveShift(Guid? id,ShiftDto dto,Guid actor,CancellationToken ct)
    {
        var start=dto.StartLocalTime.ToTimeSpan();var end=dto.EndLocalTime.ToTimeSpan()+(dto.EndsNextDay?TimeSpan.FromDays(1):TimeSpan.Zero);
        if(end<=start||end-start>TimeSpan.FromHours(24))throw new ApiException(400,"InvalidShift","Giờ kết thúc phải sau giờ bắt đầu, thời lượng tối đa 24 giờ.");
        var x=id.HasValue?await shifts.FindAsync(id.Value,ct)??throw Missing():new Shift();if(id.HasValue)Secrets.Version(db,x,dto.RowVersion);else shifts.Add(x);
        x.Code=dto.Code.Trim().ToUpperInvariant();x.Name=dto.Name.Trim();x.StartLocalTime=dto.StartLocalTime;x.EndLocalTime=dto.EndLocalTime;x.EndsNextDay=dto.EndsNextDay;x.LateGraceMinutes=dto.LateGraceMinutes;x.IsActive=dto.IsActive;
        audit.Add(actor,"Shift",x.Id,id.HasValue?"Updated":"Created",new{x.Code,x.StartLocalTime,x.EndLocalTime,x.EndsNextDay});await db.SaveChangesAsync(ct);return new{x.Id,x.Code,x.Name,x.StartLocalTime,x.EndLocalTime,x.EndsNextDay,x.LateGraceMinutes,x.IsActive,rowVersion=x.RowVersion};
    }
    public async Task DeleteShift(Guid id,Guid actor,CancellationToken ct)
    {
        var x=await shifts.FindAsync(id,ct)??throw Missing();if(await db.EmployeeShifts.AnyAsync(a=>a.ShiftId==id,ct)||await db.QrSessions.AnyAsync(q=>q.ShiftId==id,ct))throw new ApiException(409,"ShiftInUse","Ca đã được phân công hoặc có phiên QR. Hãy ngừng sử dụng ca.");shifts.Remove(x);audit.Add(actor,"Shift",id,"Deleted");await db.SaveChangesAsync(ct);
    }
    public Task<object> Locations(int page,int size,CancellationToken ct)=>Paging.Page(locations.Query().OrderBy(x=>x.Name).Select(x=>new{x.Id,x.Name,x.Latitude,x.Longitude,x.RadiusMeters,x.MaxAccuracyMeters,x.PolicyVersion,x.IsActive,rowVersion=x.RowVersion}),page,size,ct);
    public async Task<object> SaveLocation(Guid? id,LocationDto dto,Guid actor,CancellationToken ct)
    {
        Geo.Validate(dto.Latitude,dto.Longitude,dto.MaxAccuracyMeters);if(!double.IsFinite(dto.RadiusMeters))throw new ApiException(400,"InvalidRadius","Bán kính không hợp lệ.");
        var x=id.HasValue?await locations.FindAsync(id.Value,ct)??throw Missing():new WorkLocation();if(id.HasValue){Secrets.Version(db,x,dto.RowVersion);x.PolicyVersion++;}else locations.Add(x);
        x.Name=dto.Name.Trim();x.Latitude=dto.Latitude;x.Longitude=dto.Longitude;x.RadiusMeters=dto.RadiusMeters;x.MaxAccuracyMeters=dto.MaxAccuracyMeters;x.IsActive=dto.IsActive;
        audit.Add(actor,"WorkLocation",x.Id,id.HasValue?"PolicyUpdated":"Created",new{x.PolicyVersion});await db.SaveChangesAsync(ct);return new{x.Id,x.Name,x.Latitude,x.Longitude,x.RadiusMeters,x.MaxAccuracyMeters,x.PolicyVersion,x.IsActive,rowVersion=x.RowVersion};
    }
    public async Task DeleteLocation(Guid id,Guid actor,CancellationToken ct)
    {
        var x=await locations.FindAsync(id,ct)??throw Missing();if(await db.EmployeeShifts.AnyAsync(a=>a.WorkLocationId==id,ct)||await db.QrSessions.AnyAsync(q=>q.WorkLocationId==id,ct))throw new ApiException(409,"LocationInUse","Địa điểm đã được sử dụng. Hãy ngừng hoạt động.");locations.Remove(x);audit.Add(actor,"WorkLocation",id,"Deleted");await db.SaveChangesAsync(ct);
    }
    public async Task<object> Assign(Guid? id,AssignmentDto dto,Guid actor,CancellationToken ct)
    {
        await using var tx=await db.Database.BeginTransactionAsync(IsolationLevel.Serializable,ct);await TimesheetGuard.Lock(db,ct);
        var employee=await db.Employees.FromSqlInterpolated($"SELECT * FROM Employees WITH (UPDLOCK, ROWLOCK) WHERE Id={dto.EmployeeId}").SingleOrDefaultAsync(ct)??throw Missing();
        if(!employee.IsActive)throw new ApiException(400,"InactiveEmployee","Nhân viên đã ngừng hoạt động.");
        var shift=await shifts.FindAsync(dto.ShiftId,ct)??throw Missing();var location=await locations.FindAsync(dto.WorkLocationId,ct)??throw Missing();if(!shift.IsActive||!location.IsActive)throw new ApiException(400,"InactiveAssignment","Ca hoặc địa điểm đã ngừng hoạt động.");
        var start=Geo.Utc(dto.WorkDate,shift.StartLocalTime);var end=Geo.Utc(dto.WorkDate.AddDays(shift.EndsNextDay?1:0),shift.EndLocalTime);
        if(await db.EmployeeShifts.AnyAsync(x=>x.EmployeeId==dto.EmployeeId&&x.Id!=id&&x.StartUtc<end&&x.EndUtc>start,ct))throw new ApiException(409,"OverlappingShift","Nhân viên đã được phân công ca trùng thời gian.");
        var x=id.HasValue?await db.EmployeeShifts.FirstOrDefaultAsync(x=>x.Id==id,ct)??throw Missing():new EmployeeShift();
        if(id.HasValue){Secrets.Version(db,x,dto.RowVersion);if(await db.AttendanceAttempts.AnyAsync(a=>a.EmployeeShiftId==id,ct))throw new ApiException(409,"AssignmentInUse","Ca đã có lần chấm công, không được sửa.");}else db.EmployeeShifts.Add(x);
        x.SourceScheduleId=null;x.EmployeeId=dto.EmployeeId;x.ShiftId=dto.ShiftId;x.WorkLocationId=dto.WorkLocationId;x.WorkDate=dto.WorkDate;x.StartUtc=start;x.EndUtc=end;x.GraceMinutesSnapshot=shift.LateGraceMinutes;
        audit.Add(actor,"EmployeeShift",x.Id,id.HasValue?"Updated":"Created");await db.SaveChangesAsync(ct);await tx.CommitAsync(ct);return new{x.Id,x.EmployeeId,x.ShiftId,x.WorkLocationId,x.WorkDate,x.StartUtc,x.EndUtc,rowVersion=x.RowVersion};
    }
    public static ApiException Missing()=>new(404,"NotFound","Không tìm thấy dữ liệu.");
    public async Task<object> AssignRange(AssignmentRangeDto d,Guid actor,CancellationToken ct) {
        if(d.EndDate<d.WorkDate||d.EndDate.DayNumber-d.WorkDate.DayNumber>365)throw new ApiException(400,"InvalidDateRange","Chọn khoảng ngày từ 1 đến 366 ngày.");
        await using var tx=await db.Database.BeginTransactionAsync(IsolationLevel.Serializable,ct);await TimesheetGuard.Lock(db,ct);
        var employee=await db.Employees.FromSqlInterpolated($"SELECT * FROM Employees WITH (UPDLOCK, ROWLOCK) WHERE Id={d.EmployeeId}").SingleOrDefaultAsync(ct)??throw Missing();
        var shift=await db.Shifts.FindAsync([d.ShiftId],ct)??throw Missing();var location=await db.WorkLocations.FindAsync([d.WorkLocationId],ct)??throw Missing();
        if(!employee.IsActive||!shift.IsActive||!location.IsActive)throw new ApiException(400,"InactiveAssignment","Nhân viên, ca hoặc địa điểm không hoạt động.");
        var count=0;
        for(var day=d.WorkDate;day<=d.EndDate;day=day.AddDays(1)) {
            var start=Geo.Utc(day,shift.StartLocalTime);var end=Geo.Utc(day.AddDays(shift.EndsNextDay?1:0),shift.EndLocalTime);
            if(await db.EmployeeShifts.AnyAsync(x=>x.EmployeeId==d.EmployeeId&&x.StartUtc<end&&x.EndUtc>start,ct))throw new ApiException(409,"OverlappingShift","Khoảng ngày có lịch trùng. Chưa tạo lịch nào; hãy chọn lại khoảng ngày.");
            db.EmployeeShifts.Add(new(){EmployeeId=d.EmployeeId,ShiftId=d.ShiftId,WorkLocationId=d.WorkLocationId,WorkDate=day,StartUtc=start,EndUtc=end,GraceMinutesSnapshot=shift.LateGraceMinutes});count++;
        }
        audit.Add(actor,"Employee",employee.Id,"ScheduleRangeCreated",new{d.WorkDate,d.EndDate,d.ShiftId,d.WorkLocationId,count});
        await db.SaveChangesAsync(ct);await tx.CommitAsync(ct);return new{created=count};
    }
}
