using Attendance.Api.Data;
using Attendance.Api.Entities;
using Microsoft.EntityFrameworkCore;

namespace Attendance.Api.Repositories;

public interface IRepository<T> where T : Entity
{
    IQueryable<T> Query();
    Task<T?> FindAsync(Guid id, CancellationToken ct = default);
    void Add(T entity);
    void Remove(T entity);
}

public sealed class Repository<T>(AttendanceDbContext db) : IRepository<T> where T : Entity
{
    public IQueryable<T> Query() => db.Set<T>();
    public Task<T?> FindAsync(Guid id, CancellationToken ct = default) => db.Set<T>().FirstOrDefaultAsync(x => x.Id == id, ct);
    public void Add(T entity) => db.Set<T>().Add(entity);
    public void Remove(T entity) => db.Set<T>().Remove(entity);
}
