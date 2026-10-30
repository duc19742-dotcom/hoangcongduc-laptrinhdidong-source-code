namespace Attendance.Api.Entities;

public sealed class LeaveRequest : Entity
{
    public Guid EmployeeId { get; set; }
    public Employee Employee { get; set; } = null!;
    public DateOnly FromDate { get; set; }
    public DateOnly ToDate { get; set; }
    public string Kind { get; set; } = "FullDay";
    public Guid? EmployeeShiftId { get; set; }
    public DateTimeOffset? FromUtc { get; set; }
    public DateTimeOffset? ToUtc { get; set; }
    public string Reason { get; set; } = "";
    public string Status { get; set; } = "Pending";
    public Guid? ReviewedByUserId { get; set; }
    public DateTimeOffset? ReviewedAtUtc { get; set; }
    public string? DecisionReason { get; set; }
}

public sealed class TimesheetPeriod : Entity
{
    public int Year { get; set; }
    public int Month { get; set; }
    public int Revision { get; set; }
    public string Status { get; set; } = "Draft";
    public DateTimeOffset? PublishedAtUtc { get; set; }
    public DateTimeOffset? ClosedAtUtc { get; set; }
    public Guid? ClosedByUserId { get; set; }
    public string? ExceptionReason { get; set; }
}

public sealed class TimesheetSnapshot : Entity
{
    public Guid PeriodId { get; set; }
    public TimesheetPeriod Period { get; set; } = null!;
    public Guid EmployeeId { get; set; }
    public Employee Employee { get; set; } = null!;
    public int Revision { get; set; }
    public string ContentHash { get; set; } = "";
    public string DataJson { get; set; } = "";
    public string ResponseStatus { get; set; } = "Pending";
    public string? Feedback { get; set; }
    public DateTimeOffset? RespondedAtUtc { get; set; }
    public string? Resolution { get; set; }
    public Guid? ResolvedByUserId { get; set; }
    public DateTimeOffset? ResolvedAtUtc { get; set; }
}
