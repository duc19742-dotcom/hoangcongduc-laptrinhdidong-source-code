using System.Data;
using Attendance.Api.Data;
using Attendance.Api.DTOs;
using Attendance.Api.Entities;
using Attendance.Api.Middleware;
using Microsoft.EntityFrameworkCore;

namespace Attendance.Api.Services;

public sealed class EmployeeApprovalService(AttendanceDbContext db,AuditService audit)
{
 public async Task<object> ApproveRegistration(Guid id,ApproveRegistrationDto dto,Guid actor,CancellationToken ct)
 {
  await using var tx=await db.Database.BeginTransactionAsync(IsolationLevel.Serializable,ct);
  var user=await db.Users.FromSqlInterpolated($"SELECT * FROM Users WITH (UPDLOCK, ROWLOCK) WHERE Id={id}").Include(x=>x.Employee).SingleOrDefaultAsync(ct)??throw CatalogService.Missing();
  if(user.Role!="Employee"||user.ApprovalStatus!="Pending"||!user.IsActive||!user.EmailConfirmed||user.Employee is not null)
   throw new ApiException(409,"CannotApprove","Tài khoản cần xác minh email và đang chờ duyệt.");
  if(!await db.Departments.AnyAsync(x=>x.Id==dto.DepartmentId,ct))throw new ApiException(400,"InvalidDepartment","Hãy chọn phòng ban đang tồn tại.");
  if(await db.Employees.AnyAsync(x=>x.InvitationEmail.ToUpper()==user.NormalizedEmail,ct))
   throw new ApiException(409,"EmployeeProfileExists","Đã có hồ sơ cùng email. Hãy tải lại và chọn hồ sơ đó để liên kết.");
  var code=dto.EmployeeCode?.Trim().ToUpperInvariant();
  if(string.IsNullOrWhiteSpace(code)){
   var prefix="NV_"+user.NormalizedUserName;prefix=prefix[..Math.Min(prefix.Length,30)];code=prefix;
   if(await db.Employees.AnyAsync(x=>x.EmployeeCode==code,ct))
    code=prefix[..Math.Min(prefix.Length,20)]+"_"+user.Id.ToString("N")[..8].ToUpperInvariant();
  }
  if(await db.Employees.AnyAsync(x=>x.EmployeeCode==code,ct))throw new ApiException(409,"EmployeeCodeExists","Mã nhân viên đã tồn tại. Hãy dùng mã khác hoặc để trống để tạo tự động.");
  var employee=new Employee{
   EmployeeCode=code,FullName=user.FullName,InvitationEmail=user.Email,InvitationPhone=user.PhoneNumber,
   DepartmentId=dto.DepartmentId,JobTitle=string.IsNullOrWhiteSpace(dto.JobTitle)?"Nhân viên":dto.JobTitle.Trim(),
   HireDate=dto.HireDate??DateOnly.FromDateTime(DateTime.UtcNow.AddHours(7)),IsActive=true,UserId=user.Id,User=user
  };
  db.Employees.Add(employee);user.ApprovalStatus="Approved";
  audit.Add(actor,"Employee",employee.Id,"CreatedFromRegistration",new{employee.EmployeeCode,employee.DepartmentId,userId=user.Id});
  audit.Add(actor,"User",user.Id,"Approved",new{employeeId=employee.Id,source="Registration"});
  await db.SaveChangesAsync(ct);await tx.CommitAsync(ct);
  return new{user.Id,user.ApprovalStatus,employeeId=employee.Id,employee.EmployeeCode};
 }
}
