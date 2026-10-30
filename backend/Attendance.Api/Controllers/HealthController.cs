using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Attendance.Api.Controllers;

/// <summary>
/// Kiem tra API dang chay. Endpoint nay chua kiem tra ket noi SQL Server.
/// </summary>
[ApiController]
[AllowAnonymous]
[Route("api/v1/health")]
public sealed class HealthController(Attendance.Api.Data.AttendanceDbContext db) : ControllerBase
{
    /// <summary>
    /// Tra ve trang thai song cua API va thoi gian UTC tren server.
    /// </summary>
    [HttpGet("live")]
    [ProducesResponseType<HealthResponse>(StatusCodes.Status200OK)]
    public ActionResult<HealthResponse> Live()
    {
        return Ok(new HealthResponse(
            Status: "Healthy",
            Service: "Attendance.Api",
            ServerTimeUtc: DateTimeOffset.UtcNow));
    }

    [HttpGet("ready")]
    public async Task<IActionResult> Ready(CancellationToken ct)
    {
        try { return await db.Database.CanConnectAsync(ct) && !(await db.Database.GetPendingMigrationsAsync(ct)).Any() ? Ok(new {status="Ready",database="Connected"}) : StatusCode(503,new{status="NotReady"}); }
        catch { return StatusCode(503,new{status="NotReady"}); }
    }
}

public sealed record HealthResponse(
    string Status,
    string Service,
    DateTimeOffset ServerTimeUtc);
