using System.ComponentModel.DataAnnotations;

namespace Attendance.Api.Entities;

public abstract class Entity
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public DateTimeOffset CreatedAtUtc { get; set; } = DateTimeOffset.UtcNow;
    [Timestamp] public byte[] RowVersion { get; set; } = [];
}

public sealed class AppUser : Entity
{
    public string? DisplayName { get; set; }
    public string? AvatarDataUrl { get; set; }
    public string FullName { get; set; } = "";
    public string UserName { get; set; } = "";
    public string NormalizedUserName { get; set; } = "";
    public string Email { get; set; } = "";
    public string NormalizedEmail { get; set; } = "";
    public string PhoneNumber { get; set; } = "";
    public string PasswordHash { get; set; } = "";
    public string Role { get; set; } = "Employee";
    public string ApprovalStatus { get; set; } = "Pending";
    public bool EmailConfirmed { get; set; }
    public bool PhoneNumberConfirmed { get; set; }
    public bool IsActive { get; set; } = true;
    public Employee? Employee { get; set; }
}

public sealed class Department : Entity
{
    public string Code { get; set; } = "";
    public string Name { get; set; } = "";
}

public sealed class Employee : Entity
{
    public string EmployeeCode { get; set; } = "";
    public string FullName { get; set; } = "";
    public string InvitationEmail { get; set; } = "";
    public string InvitationPhone { get; set; } = "";
    public string JobTitle { get; set; } = "";
    public DateOnly HireDate { get; set; }
    public bool IsActive { get; set; } = true;
    public Guid DepartmentId { get; set; }
    public Department Department { get; set; } = null!;
    public Guid? UserId { get; set; }
    public AppUser? User { get; set; }
}

public sealed class Shift : Entity
{
    public string Code { get; set; } = "";
    public string Name { get; set; } = "";
    public TimeOnly StartLocalTime { get; set; }
    public TimeOnly EndLocalTime { get; set; }
    public bool EndsNextDay { get; set; }
    public int LateGraceMinutes { get; set; } = 5;
    public bool IsActive { get; set; } = true;
}

public sealed class WorkLocation : Entity
{
    public string Name { get; set; } = "";
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public double RadiusMeters { get; set; } = 150;
    public double MaxAccuracyMeters { get; set; } = 50;
    public int PolicyVersion { get; set; } = 1;
    public bool IsActive { get; set; } = true;
}

public sealed class EmployeeShift : Entity
{
    public Guid? SourceScheduleId { get; set; }
    public Guid EmployeeId { get; set; }
    public Employee Employee { get; set; } = null!;
    public Guid ShiftId { get; set; }
    public Shift Shift { get; set; } = null!;
    public Guid WorkLocationId { get; set; }
    public WorkLocation WorkLocation { get; set; } = null!;
    public DateOnly WorkDate { get; set; }
    public DateTimeOffset StartUtc { get; set; }
    public DateTimeOffset EndUtc { get; set; }
    public int GraceMinutesSnapshot { get; set; }
}

public sealed class QrSession : Entity
{
    public string TokenHash { get; set; } = "";
    public Guid CreatedByUserId { get; set; }
    public Guid ShiftId { get; set; }
    public Shift Shift { get; set; } = null!;
    public Guid WorkLocationId { get; set; }
    public WorkLocation WorkLocation { get; set; } = null!;
    public DateOnly WorkDate { get; set; }
    public string Action { get; set; } = "CheckIn";
    public DateTimeOffset ExpiresAtUtc { get; set; }
    public DateTimeOffset? RevokedAtUtc { get; set; }
}

public sealed class AttendanceAttempt : Entity
{
    public Guid EmployeeId { get; set; }
    public Employee Employee { get; set; } = null!;
    public Guid EmployeeShiftId { get; set; }
    public EmployeeShift EmployeeShift { get; set; } = null!;
    public Guid? QrSessionId { get; set; }
    public QrSession? QrSession { get; set; }
    public string Action { get; set; } = "CheckIn";
    public DateTimeOffset ReceivedAtUtc { get; set; }
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public double AccuracyMeters { get; set; }
    public double DistanceMeters { get; set; }
    public string Outcome { get; set; } = "NeedsReview";
    public string ReasonCode { get; set; } = "";
    public string PolicySnapshotJson { get; set; } = "{}";
    public Guid IdempotencyKey { get; set; }
    public string PayloadHash { get; set; } = "";
}

public sealed class QrRedemption : Entity
{
    public Guid? QrSessionId { get; set; }
    public QrSession? QrSession { get; set; }
    public Guid EmployeeId { get; set; }
    public Employee Employee { get; set; } = null!;
    public Guid AttemptId { get; set; }
    public AttendanceAttempt Attempt { get; set; } = null!;
}

public sealed class AttendanceRecord : Entity
{
    public Guid EmployeeShiftId { get; set; }
    public EmployeeShift EmployeeShift { get; set; } = null!;
    public Guid? AttemptId { get; set; }
    public AttendanceAttempt Attempt { get; set; } = null!;
    public string Action { get; set; } = "CheckIn";
    public DateTimeOffset EffectiveAtUtc { get; set; }
    public DateTimeOffset RecordedAtUtc { get; set; }
    public string Source { get; set; } = "Automatic";
    public Guid? ApprovedRequestId { get; set; }
}

public sealed class AttendanceRequest : Entity
{
    public Guid AttemptId { get; set; }
    public AttendanceAttempt Attempt { get; set; } = null!;
    public Guid EmployeeId { get; set; }
    public Employee Employee { get; set; } = null!;
    public string Reason { get; set; } = "";
    public string Status { get; set; } = "Pending";
    public Guid? ReviewedByUserId { get; set; }
    public DateTimeOffset? ReviewedAtUtc { get; set; }
    public string? DecisionReason { get; set; }
}

public sealed class AttendanceRequestEvent : Entity
{
    public Guid RequestId { get; set; }
    public AttendanceRequest Request { get; set; } = null!;
    public Guid ActorUserId { get; set; }
    public string? OldStatus { get; set; }
    public string NewStatus { get; set; } = "Pending";
    public string Note { get; set; } = "";
}

public sealed class AuthFlow : Entity
{
    public Guid UserId { get; set; }
    public AppUser User { get; set; } = null!;
    public string TokenHash { get; set; } = "";
    public string Purpose { get; set; } = "Login";
    public DateTimeOffset ExpiresAtUtc { get; set; }
    public DateTimeOffset? UsedAtUtc { get; set; }
    public DateTimeOffset? LastSentAtUtc { get; set; }
    public int SendCount { get; set; }
    public Guid? ExternalChallengeId { get; set; }
    public DateTimeOffset? ExternalChallengeStartedAtUtc { get; set; }
    public DateTimeOffset? ExternalChallengeExpiresAtUtc { get; set; }
    public int ExternalVerificationAttempts { get; set; }
}

public sealed class ExternalAuthProof : Entity
{
    public Guid UserId { get; set; }
    public AppUser User { get; set; } = null!;
    public string Provider { get; set; } = "Firebase";
    public string ProofHash { get; set; } = "";
    public string SubjectDigest { get; set; } = "";
    public DateTimeOffset AuthenticatedAtUtc { get; set; }
}

public sealed class OtpChallenge : Entity
{
    public Guid FlowId { get; set; }
    public AuthFlow Flow { get; set; } = null!;
    public Guid UserId { get; set; }
    public string Purpose { get; set; } = "Login";
    public string Channel { get; set; } = "Email";
    public string DestinationDigest { get; set; } = "";
    public string CodeMac { get; set; } = "";
    public DateTimeOffset ExpiresAtUtc { get; set; }
    public DateTimeOffset? ConsumedAtUtc { get; set; }
    public DateTimeOffset? SupersededAtUtc { get; set; }
    public int FailedAttempts { get; set; }
    public string DeliveryStatus { get; set; } = "Pending";
    public string? ProviderMessageId { get; set; }
}

public sealed class AuthSession : Entity
{
    public string AuthenticationMethod { get; set; } = "Legacy";
    public Guid UserId { get; set; }
    public AppUser User { get; set; } = null!;
    public string JtiHash { get; set; } = "";
    public DateTimeOffset ExpiresAtUtc { get; set; }
    public DateTimeOffset? RevokedAtUtc { get; set; }
}

public sealed class AuditLog : Entity
{
    public Guid? ActorUserId { get; set; }
    public string EntityType { get; set; } = "";
    public Guid? EntityId { get; set; }
    public string Action { get; set; } = "";
    public string DetailsJson { get; set; } = "{}";
}
