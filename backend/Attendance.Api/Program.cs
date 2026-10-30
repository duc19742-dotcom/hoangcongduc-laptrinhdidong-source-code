using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using System.Threading.RateLimiting;
using Attendance.Api.Data;
using Attendance.Api.Entities;
using Attendance.Api.Middleware;
using Attendance.Api.Repositories;
using Attendance.Api.Services;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi;

var builder=WebApplication.CreateBuilder(args);
if(builder.Environment.IsDevelopment()) builder.Configuration.AddJsonFile(Path.GetFullPath(Path.Combine(builder.Environment.ContentRootPath,"../../.local/secrets.json")),optional:true,reloadOnChange:false);
builder.Configuration.AddEnvironmentVariables();
var signingKey=builder.Configuration["Jwt:SigningKey"];
if(string.IsNullOrWhiteSpace(signingKey)||Encoding.UTF8.GetByteCount(signingKey)<32||string.IsNullOrWhiteSpace(builder.Configuration["Otp:HmacKey"])) throw new InvalidOperationException("Configure JWT and OTP keys. Development: run scripts/Initialize-Local.ps1.");
builder.Services.AddControllers(); builder.Services.AddSwaggerGen(c=> {
 c.SwaggerDoc("v1",new OpenApiInfo {Title="Đức Attendance API",Version="v1",Description="API chấm công nhân viên. JWT chỉ được cấp sau khi xác minh OTP."});
 c.AddSecurityDefinition("Bearer",new OpenApiSecurityScheme {Type=SecuritySchemeType.Http,Scheme="bearer",BearerFormat="JWT"});
 c.AddSecurityRequirement(document=>new OpenApiSecurityRequirement {[new OpenApiSecuritySchemeReference("Bearer",document)]=[]});
});
builder.Services.AddDbContext<AttendanceDbContext>(o=>o.UseSqlServer(builder.Configuration.GetConnectionString("DefaultConnection")??throw new InvalidOperationException("Connection string missing.")));
builder.Services.AddScoped(typeof(IRepository<>),typeof(Repository<>));
builder.Services.AddScoped<IPasswordHasher<AppUser>,PasswordHasher<AppUser>>();
builder.Services.AddScoped<AuthService>();builder.Services.AddScoped<AuditService>();builder.Services.AddScoped<CatalogService>();builder.Services.AddScoped<IMessageSender,MessageSender>();
builder.Services.AddScoped<AttendanceService>();
builder.Services.AddScoped<EmployeeApprovalService>();
builder.Services.AddScoped<RememberedDeviceService>();
builder.Services.AddScoped<BiometricService>();
builder.Services.AddScoped<ProfileService>();
builder.Services.AddScoped<SiteQrService>();
builder.Services.AddScoped<WorkScheduleService>();
builder.Services.AddScoped<TimesheetService>();
builder.Services.AddScoped<LeaveService>();
builder.Services.AddHttpClient("Messaging",c=>c.Timeout=TimeSpan.FromSeconds(20));
builder.Services.AddMemoryCache();builder.Services.AddScoped<IFirebasePhoneVerifier,FirebasePhoneVerifier>();builder.Services.AddScoped<FirebasePhoneFlowService>();
builder.Services.AddHttpClient("FirebaseKeys",c=>c.Timeout=TimeSpan.FromSeconds(15));
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(o=> {
 o.TokenValidationParameters=new TokenValidationParameters {ValidateIssuer=true,ValidateAudience=true,ValidateLifetime=true,ValidateIssuerSigningKey=true,ValidIssuer=builder.Configuration["Jwt:Issuer"],ValidAudience=builder.Configuration["Jwt:Audience"],IssuerSigningKey=new SymmetricSecurityKey(Encoding.UTF8.GetBytes(signingKey)),ClockSkew=TimeSpan.FromSeconds(15)};
 o.Events=new JwtBearerEvents {OnTokenValidated=async context=> {
  var db=context.HttpContext.RequestServices.GetRequiredService<AttendanceDbContext>();var idText=context.Principal?.FindFirstValue(ClaimTypes.NameIdentifier);var jti=context.Principal?.FindFirstValue(JwtRegisteredClaimNames.Jti);
  if(!Guid.TryParse(idText,out var id)||jti is null){context.Fail("Invalid token.");return;}
  var u=await db.Users.Include(x=>x.Employee).FirstOrDefaultAsync(x=>x.Id==id,context.HttpContext.RequestAborted);
  if(u is null||u.Role!=context.Principal!.FindFirstValue(ClaimTypes.Role)){context.Fail("Account changed.");return;}
  try{AuthService.RequireApproved(u);}catch(ApiException){context.Fail("Account inactive.");return;}
  var hash=Secrets.Hash(jti);if(!await db.AuthSessions.AnyAsync(x=>x.UserId==id&&x.JtiHash==hash&&!x.RevokedAtUtc.HasValue&&x.ExpiresAtUtc>DateTimeOffset.UtcNow,context.HttpContext.RequestAborted))context.Fail("Session expired or revoked.");
 }};
});
builder.Services.AddAuthorization(o=>o.FallbackPolicy=new Microsoft.AspNetCore.Authorization.AuthorizationPolicyBuilder().RequireAuthenticatedUser().Build());
builder.Services.AddRateLimiter(o=> {
 o.RejectionStatusCode=429;
 o.AddPolicy("auth",context=>RateLimitPartition.GetFixedWindowLimiter(context.Connection.RemoteIpAddress?.ToString()??"unknown",_=>new FixedWindowRateLimiterOptions {PermitLimit=20,Window=TimeSpan.FromMinutes(1),QueueLimit=0}));
 o.GlobalLimiter=PartitionedRateLimiter.Create<HttpContext,string>(context=>RateLimitPartition.GetFixedWindowLimiter(context.Connection.RemoteIpAddress?.ToString()??"unknown",_=>new FixedWindowRateLimiterOptions {PermitLimit=180,Window=TimeSpan.FromMinutes(1),QueueLimit=0}));
 o.OnRejected=async(context,ct)=>{context.HttpContext.Response.Headers.RetryAfter="60";await context.HttpContext.Response.WriteAsJsonAsync(new {status=429,code="RateLimit",detail="Quá nhiều yêu cầu. Hãy thử lại sau 60 giây."},ct);};
});
var app=builder.Build();
if(builder.Configuration.GetValue("Setup:RunOnStartup",false)) {
 using var scope=app.Services.CreateScope();
 var db=scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();await db.Database.MigrateAsync();
 if(!await db.Users.AnyAsync(x=>x.Role=="Admin"))await scope.ServiceProvider.GetRequiredService<AuthService>().Bootstrap(CancellationToken.None);
}
if(args.Contains("--migrate")||args.Contains("--bootstrap-admin")) {
 using var scope=app.Services.CreateScope();
 if(args.Contains("--migrate"))await scope.ServiceProvider.GetRequiredService<AttendanceDbContext>().Database.MigrateAsync();
 if(args.Contains("--bootstrap-admin"))await scope.ServiceProvider.GetRequiredService<AuthService>().Bootstrap(CancellationToken.None);
 return;
}
app.UseMiddleware<ApiExceptionMiddleware>();
app.UseStaticFiles();
if(!app.Environment.IsDevelopment()){app.UseHsts();app.UseHttpsRedirection();}
if(app.Environment.IsDevelopment()||builder.Configuration.GetValue("Swagger:Enabled",false)){app.UseSwagger();app.UseSwaggerUI();}
app.UseRateLimiter();app.UseAuthentication();app.UseAuthorization();app.MapControllers();app.MapGet("/",()=>Results.Redirect("/display.html")).AllowAnonymous();app.Run();
public partial class Program { }
