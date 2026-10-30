using System.Diagnostics;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace Attendance.Api.Middleware;

public sealed class ApiException(int status, string code, string message) : Exception(message)
{
    public int Status { get; } = status;
    public string Code { get; } = code;
}

public sealed class ApiExceptionMiddleware(RequestDelegate next, ILogger<ApiExceptionMiddleware> logger)
{
    public async Task InvokeAsync(HttpContext context)
    {
        try { await next(context); }
        catch (Exception ex) when (!context.Response.HasStarted)
        {
            var (status, code, detail) = ex switch
            {
                ApiException a => (a.Status, a.Code, a.Message),
                DbUpdateConcurrencyException => (409, "ConcurrentUpdate", "Dữ liệu vừa được thay đổi. Hãy tải lại và thử lại."),
                DbUpdateException { InnerException: SqlException { Number: 2601 or 2627 } } => (409, "DuplicateData", "Dữ liệu bị trùng. Hãy kiểm tra lại."),
                DbUpdateException { InnerException: SqlException { Number: 547 } } => (409, "ReferencedData", "Dữ liệu đang được tham chiếu hoặc không đúng ràng buộc."),
                SqlException { Number: 1205 } => (409, "ConcurrentUpdate", "Có yêu cầu đang xử lý đồng thời. Hãy thử lại."),
                SqlException => (503, "DatabaseUnavailable", "Chưa kết nối được cơ sở dữ liệu."),
                _ => (500, "UnexpectedError", "Hệ thống gặp lỗi. Hãy thử lại hoặc cung cấp mã tra cứu cho quản trị viên.")
            };
            if (status >= 500) logger.LogError("API failure {Code}; trace {TraceId}; exception type {Type}", code, context.TraceIdentifier, ex.GetType().Name);
            context.Response.StatusCode = status;
            await context.Response.WriteAsJsonAsync(new {
                type = "about:blank", title = "Không thể thực hiện yêu cầu", status, code, detail,
                traceId = Activity.Current?.Id ?? context.TraceIdentifier
            });
        }
    }
}
