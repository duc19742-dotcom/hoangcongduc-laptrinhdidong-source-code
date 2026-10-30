using System.ComponentModel.DataAnnotations;

namespace Attendance.Api.DTOs;

public sealed record RegisterDto(
    [Required, StringLength(120, MinimumLength = 2)] string FullName,
    [Required, RegularExpression(@"^[A-Za-z0-9_.]{3,32}$")] string Username,
    [Required, EmailAddress, StringLength(254)] string Email,
    [Required, StringLength(20)] string Phone,
    [Required, StringLength(128, MinimumLength = 12)] string Password,
    [Required] string ConfirmPassword);
public sealed record LoginDto([Required] string Username, [Required] string Password);
public record FlowDto(Guid FlowId, [Required] string FlowToken);
public sealed record FirebaseVerifyDto(Guid FlowId,[Required] string FlowToken,Guid ChallengeId,[Required,StringLength(8192,MinimumLength=20)] string IdToken) : FlowDto(FlowId,FlowToken);
public sealed record SendOtpDto(Guid FlowId, [Required] string FlowToken, [Required] string Channel) : FlowDto(FlowId, FlowToken);
public record VerifyOtpDto(Guid FlowId, [Required] string FlowToken, Guid ChallengeId, [Required, RegularExpression(@"^\d{6}$")] string Code) : FlowDto(FlowId, FlowToken);
public sealed record ResetPasswordDto(Guid FlowId, [Required] string FlowToken, Guid ChallengeId, [Required, RegularExpression(@"^\d{6}$")] string Code, [Required] string NewPassword, [Required] string ConfirmPassword) : VerifyOtpDto(FlowId, FlowToken, ChallengeId, Code);
public sealed record ForgotDto([Required, EmailAddress] string Email);
public sealed record DecisionDto([Required, StringLength(1000, MinimumLength = 5)] string Reason, string? RowVersion = null);
public sealed record ApproveUserDto(Guid EmployeeId);
public sealed record ApproveRegistrationDto(Guid DepartmentId,[StringLength(30)] string? EmployeeCode=null,[StringLength(100)] string? JobTitle=null,DateOnly? HireDate=null);
public sealed record DepartmentDto([Required, StringLength(30, MinimumLength = 1)] string Code, [Required, StringLength(120, MinimumLength = 2)] string Name, string? RowVersion = null);
public sealed record EmployeeDto([Required, StringLength(30)] string EmployeeCode, [Required, StringLength(120, MinimumLength = 2)] string FullName,
    [Required, EmailAddress] string Email, [Required] string Phone, Guid DepartmentId,
    [StringLength(100)] string JobTitle, DateOnly HireDate, bool IsActive = true, string? RowVersion = null);
public sealed record EmployeeStatusDto(bool IsActive, [Required, StringLength(1000, MinimumLength = 5)] string Reason);
public sealed record ShiftDto([Required, StringLength(30)] string Code, [Required, StringLength(120)] string Name,
    TimeOnly StartLocalTime, TimeOnly EndLocalTime, bool EndsNextDay, [Range(0,120)] int LateGraceMinutes = 5, bool IsActive = true, string? RowVersion = null);
public sealed record LocationDto([Required, StringLength(120)] string Name, [Range(-90,90)] double Latitude, [Range(-180,180)] double Longitude,
    [Range(1,10000)] double RadiusMeters = 150, [Range(1,1000)] double MaxAccuracyMeters = 50, bool IsActive = true, string? RowVersion = null);
public sealed record PositionDto([Range(-90,90)] double Latitude, [Range(-180,180)] double Longitude, [Range(0.1,100000)] double AccuracyMeters);
public sealed record AssignmentDto(Guid EmployeeId, Guid ShiftId, Guid WorkLocationId, DateOnly WorkDate, string? RowVersion = null);
public sealed record AssignmentRangeDto(Guid EmployeeId,Guid ShiftId,Guid WorkLocationId,DateOnly WorkDate,DateOnly EndDate);
public sealed record QrCreateDto(Guid ShiftId, Guid WorkLocationId, DateOnly WorkDate, [Required] string Action, [Range(30,120)] int TtlSeconds = 60);
public sealed record QrVerifyDto([Required] string QrToken, Guid EmployeeShiftId, [Required] string Action);
public sealed record QrRenderDto([Required,StringLength(128)] string QrToken);
public sealed record AttendanceSubmitDto(Guid EmployeeShiftId, string? QrToken, [Range(-90,90)] double Latitude,
    [Range(-180,180)] double Longitude, [Range(0.1,100000)] double AccuracyMeters,
    [property: System.Text.Json.Serialization.JsonIgnore(Condition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull)] DateTimeOffset? CapturedAtUtc = null);
public sealed record RequestCreateDto(Guid AttemptId, [Required, StringLength(1000, MinimumLength = 10)] string Reason);
public sealed record RequestEditDto([Required, StringLength(1000, MinimumLength = 10)] string Reason, [Required] string RowVersion);
