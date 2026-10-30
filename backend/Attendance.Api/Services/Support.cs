using System.Globalization;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Attendance.Api.Data;
using Attendance.Api.Entities;
using Attendance.Api.Middleware;
using Microsoft.EntityFrameworkCore;

namespace Attendance.Api.Services;

public static class Secrets
{
    public static string NewToken() => Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
    public static string Hash(string value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value)));
    public static bool Equal(string a, string b) => CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(a), Encoding.UTF8.GetBytes(b));
    public static string Normalize(string value) => value.Trim().ToUpperInvariant();
    public static string Phone(string input)
    {
        var value = input.Replace(" ", "").Replace("-", "").Trim();
        if (value.StartsWith('0')) value = "+84" + value[1..];
        if (!System.Text.RegularExpressions.Regex.IsMatch(value, @"^\+[1-9]\d{7,14}$"))
            throw new ApiException(400, "InvalidPhone", "Số điện thoại không hợp lệ. Hãy nhập định dạng +84 hoặc số di động Việt Nam.");
        return value;
    }
    public static void Password(string password, string confirm)
    {
        if (password != confirm || password.Length is < 12 or > 128 || !password.Any(char.IsUpper) || !password.Any(char.IsLower) || !password.Any(char.IsDigit) || !password.Any(c => !char.IsLetterOrDigit(c)))
            throw new ApiException(400, "WeakPassword", "Mật khẩu phải khớp xác nhận, dài 12–128 ký tự, gồm chữ hoa, chữ thường, số và ký tự đặc biệt.");
    }
    public static Guid UserId(this ClaimsPrincipal user) => Guid.Parse(user.FindFirstValue(ClaimTypes.NameIdentifier)!);
    public static bool Admin(this ClaimsPrincipal user) => user.IsInRole("Admin");
    public static void Version(AttendanceDbContext db, Entity entity, string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) throw new ApiException(400, "MissingVersion", "Thiếu phiên bản dữ liệu. Hãy tải lại.");
        byte[] version;
        try { version = Convert.FromBase64String(value); } catch (FormatException) { throw new ApiException(400,"InvalidVersion","Phiên bản dữ liệu không hợp lệ."); }
        db.Entry(entity).Property(x => x.RowVersion).OriginalValue = version;
    }
}

public sealed class AuditService(AttendanceDbContext db)
{
    public void Add(Guid? actor, string entity, Guid? id, string action, object? details = null) => db.AuditLogs.Add(new AuditLog {
        ActorUserId = actor, EntityType = entity, EntityId = id, Action = action,
        DetailsJson = JsonSerializer.Serialize(details ?? new { })
    });
}

public static class Geo
{
    public static void Validate(double lat, double lon, double accuracy)
    {
        if (!double.IsFinite(lat) || !double.IsFinite(lon) || !double.IsFinite(accuracy) || lat is < -90 or > 90 || lon is < -180 or > 180 || accuracy <= 0)
            throw new ApiException(400,"InvalidPosition","Tọa độ hoặc độ chính xác GPS không hợp lệ.");
    }
    public static double Distance(double lat1, double lon1, double lat2, double lon2)
    {
        const double rad = Math.PI / 180;
        var a = Math.Pow(Math.Sin((lat2-lat1)*rad/2),2) + Math.Cos(lat1*rad)*Math.Cos(lat2*rad)*Math.Pow(Math.Sin((lon2-lon1)*rad/2),2);
        return 6371000 * 2 * Math.Asin(Math.Sqrt(Math.Clamp(a,0,1)));
    }
    public static DateTimeOffset Utc(DateOnly date, TimeOnly time) => new DateTimeOffset(date.ToDateTime(time), TimeSpan.FromHours(7)).ToUniversalTime();
}

public static class Paging
{
    public static async Task<object> Page<T>(IQueryable<T> q, int page, int pageSize, CancellationToken ct)
    {
        page = Math.Max(1,page); pageSize = Math.Clamp(pageSize,1,100);
        return new { items = await q.Skip((page-1)*pageSize).Take(pageSize).ToListAsync(ct), page, pageSize, totalCount = await q.CountAsync(ct) };
    }
    public static (DateTimeOffset Start, DateTimeOffset End) Dates(DateOnly? from, DateOnly? to)
    {
        var today = DateOnly.FromDateTime(DateTime.UtcNow.AddHours(7));
        var start = from ?? today.AddDays(-30); var end = to ?? today;
        if (end < start || end.DayNumber-start.DayNumber > 93) throw new ApiException(400,"InvalidRange","Khoảng ngày tối đa 93 ngày và ngày kết thúc không trước ngày bắt đầu.");
        return (Geo.Utc(start, TimeOnly.MinValue), Geo.Utc(end.AddDays(1), TimeOnly.MinValue));
    }
}
