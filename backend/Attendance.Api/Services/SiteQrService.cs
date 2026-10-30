using Attendance.Api.Data;
using Attendance.Api.Entities;
using Attendance.Api.Middleware;
using Microsoft.EntityFrameworkCore;
namespace Attendance.Api.Services;

public sealed class SiteQrSession:Entity {
 public string TokenHash {get;set;}="";
 public Guid WorkLocationId {get;set;}
 public WorkLocation WorkLocation {get;set;}=null!;
 public DateTimeOffset ExpiresAtUtc {get;set;}
 public DateTimeOffset? RevokedAtUtc {get;set;}
}
public sealed record SiteQrDto(Guid WorkLocationId);
public sealed class SiteDisplay:Entity {
 public string TokenHash{get;set;}="";
 public Guid WorkLocationId{get;set;}
 public Guid CreatedByUserId{get;set;}
 public DateTimeOffset ExpiresAtUtc{get;set;}
}
public sealed record SiteDisplayDto(string DisplayToken);
public sealed class SiteQrService(AttendanceDbContext db,AuditService audit) {
 public async Task<object> BeginDisplay(Guid location,Guid actor,CancellationToken ct) {
  if(!await db.WorkLocations.AnyAsync(x=>x.Id==location&&x.IsActive,ct))throw CatalogService.Missing();
  var token=Secrets.NewToken();var expires=DateTimeOffset.UtcNow.AddHours(12);
  db.Add(new SiteDisplay{TokenHash=Secrets.Hash(token),WorkLocationId=location,CreatedByUserId=actor,ExpiresAtUtc=expires});audit.Add(actor,"WorkLocation",location,"DisplayStarted");await db.SaveChangesAsync(ct);return new{displayToken=token,expiresAtUtc=expires};
 }
 public async Task<object> FromDisplay(string token,CancellationToken ct) {
  if(string.IsNullOrWhiteSpace(token)||token.Length>256)throw new ApiException(401,"InvalidDisplay","Phiên màn hình đã hết hạn.");
  var hash=Secrets.Hash(token);var display=await db.Set<SiteDisplay>().SingleOrDefaultAsync(x=>x.TokenHash==hash&&x.ExpiresAtUtc>DateTimeOffset.UtcNow,ct);
  if(display is null||!await db.Users.AnyAsync(x=>x.Id==display.CreatedByUserId&&x.IsActive&&x.Role=="Admin"&&x.ApprovalStatus=="Approved",ct))throw new ApiException(401,"InvalidDisplay","Phiên màn hình đã hết hạn. Admin cần mở lại màn hình.");
  return await Create(display.WorkLocationId,display.CreatedByUserId,ct);
 }
 public async Task<object> Create(Guid location,Guid actor,CancellationToken ct) {
  if(!await db.WorkLocations.AnyAsync(x=>x.Id==location&&x.IsActive,ct))throw CatalogService.Missing();
  var token="site_"+Secrets.NewToken();var now=DateTimeOffset.UtcNow;
  // A display may refresh just before expiry; the previous token remains valid only until its original expiry.
  var q=new SiteQrSession{TokenHash=Secrets.Hash(token),WorkLocationId=location,ExpiresAtUtc=now.AddSeconds(60)};
  db.Set<SiteQrSession>().Add(q);audit.Add(actor,"SiteQr",q.Id,"Created",new{location,q.ExpiresAtUtc});await db.SaveChangesAsync(ct);
  return new{id=q.Id,qrToken=token,q.ExpiresAtUtc,serverTimeUtc=now};
 }
}
