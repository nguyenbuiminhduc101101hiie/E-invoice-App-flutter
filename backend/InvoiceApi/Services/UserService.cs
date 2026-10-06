using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Dapper;
using InvoiceApi.Infrastructure;
using InvoiceApi.Models;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;

namespace InvoiceApi.Services;

public static class Roles
{
    public const string Admin = "Admin";
    public const string User = "User";

    public static string Normalize(string? role) =>
        string.Equals(role, Admin, StringComparison.OrdinalIgnoreCase) ? Admin : User;
}

public class UserService(Db db, IOptions<JwtOptions> jwtOptions)
{
    private readonly JwtOptions _jwt = jwtOptions.Value;

    public const string CreateTableSql = """
        IF OBJECT_ID(N'dbo.AppUsers', N'U') IS NULL
        BEGIN
            CREATE TABLE dbo.AppUsers (
                Id           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AppUsers PRIMARY KEY,
                Username     NVARCHAR(50)  NOT NULL,
                PasswordHash NVARCHAR(200) NOT NULL,
                FullName     NVARCHAR(100) NULL,
                Role         NVARCHAR(20)  NOT NULL CONSTRAINT DF_AppUsers_Role DEFAULT (N'User'),
                IsActive     BIT           NOT NULL CONSTRAINT DF_AppUsers_IsActive DEFAULT (1),
                CreatedAt    DATETIME2(0)  NOT NULL CONSTRAINT DF_AppUsers_CreatedAt DEFAULT (SYSDATETIME()),
                LastLoginAt  DATETIME2(0)  NULL,
                CONSTRAINT UQ_AppUsers_Username UNIQUE (Username)
            );
        END
        """;

    public async Task EnsureTableAsync()
    {
        await using var cnn = await db.OpenAsync();
        await cnn.ExecuteAsync(CreateTableSql);
    }

    private class LoginRow
    {
        public int Id { get; set; }
        public string PasswordHash { get; set; } = "";
        public bool IsActive { get; set; }
    }

    private const string SelectUser = "SELECT Id, Username, FullName, Role, IsActive, CreatedAt, LastLoginAt FROM dbo.AppUsers";

    public async Task<bool> NeedsSetupAsync()
    {
        await using var cnn = await db.OpenAsync();
        return await cnn.ExecuteScalarAsync<int>("SELECT COUNT(*) FROM dbo.AppUsers") == 0;
    }

    public async Task<LoginResponse> LoginAsync(LoginRequest req)
    {
        await using var cnn = await db.OpenAsync();
        var user = await cnn.QuerySingleOrDefaultAsync<LoginRow>(
            "SELECT Id, PasswordHash, IsActive FROM dbo.AppUsers WHERE Username = @u", new { u = req.Username.Trim() });

        if (user == null || !BCrypt.Net.BCrypt.Verify(req.Password, user.PasswordHash))
            throw new AppException("Sai tên đăng nhập hoặc mật khẩu.", 401);
        if (!user.IsActive)
            throw new AppException("Tài khoản đã bị khóa. Liên hệ quản trị viên.", 403);

        await cnn.ExecuteAsync("UPDATE dbo.AppUsers SET LastLoginAt = SYSDATETIME() WHERE Id = @id", new { id = user.Id });
        var dto = await GetAsync(user.Id);
        return IssueToken(dto);
    }

    public async Task<LoginResponse> SetupFirstAdminAsync(SetupRequest req)
    {
        ValidateCredentials(req.Username, req.Password);
        await using var cnn = await db.OpenAsync();
        // Chỉ cho phép khi chưa có tài khoản nào; điều kiện nằm trong câu INSERT để tránh 2 request đồng thời
        var id = await cnn.ExecuteScalarAsync<int?>("""
            INSERT INTO dbo.AppUsers (Username, PasswordHash, FullName, Role)
            OUTPUT INSERTED.Id
            SELECT @Username, @Hash, @FullName, N'Admin'
            WHERE NOT EXISTS (SELECT 1 FROM dbo.AppUsers WITH (UPDLOCK, HOLDLOCK))
            """, new { Username = req.Username.Trim(), Hash = BCrypt.Net.BCrypt.HashPassword(req.Password), req.FullName });
        if (id == null) throw new AppException("Hệ thống đã có tài khoản quản trị.", 409);
        return IssueToken(await GetAsync(id.Value));
    }

    public async Task<UserDto> GetAsync(int id)
    {
        await using var cnn = await db.OpenAsync();
        return await cnn.QuerySingleOrDefaultAsync<UserDto>(SelectUser + " WHERE Id = @id", new { id })
               ?? throw new AppException("Không tìm thấy tài khoản.", 404);
    }

    public async Task<List<UserDto>> ListAsync()
    {
        await using var cnn = await db.OpenAsync();
        return (await cnn.QueryAsync<UserDto>(SelectUser + " ORDER BY Username")).ToList();
    }

    public async Task<UserDto> CreateAsync(CreateUserRequest req)
    {
        ValidateCredentials(req.Username, req.Password);
        await using var cnn = await db.OpenAsync();
        var exists = await cnn.ExecuteScalarAsync<int>("SELECT COUNT(*) FROM dbo.AppUsers WHERE Username = @u", new { u = req.Username.Trim() });
        if (exists > 0) throw new AppException("Tên đăng nhập đã tồn tại.", 409);

        var id = await cnn.ExecuteScalarAsync<int>("""
            INSERT INTO dbo.AppUsers (Username, PasswordHash, FullName, Role)
            OUTPUT INSERTED.Id VALUES (@Username, @Hash, @FullName, @Role)
            """, new
        {
            Username = req.Username.Trim(),
            Hash = BCrypt.Net.BCrypt.HashPassword(req.Password),
            FullName = req.FullName?.Trim(),
            Role = Roles.Normalize(req.Role),
        });
        return await GetAsync(id);
    }

    public async Task<UserDto> UpdateAsync(int id, UpdateUserRequest req, int currentUserId)
    {
        var role = Roles.Normalize(req.Role);
        if (id == currentUserId && (role != Roles.Admin || !req.IsActive))
            throw new AppException("Không thể tự hạ quyền hoặc khóa chính tài khoản của bạn.");
        if (!string.IsNullOrEmpty(req.NewPassword)) ValidatePassword(req.NewPassword);

        await using var cnn = await db.OpenAsync();
        var affected = await cnn.ExecuteAsync("""
            UPDATE dbo.AppUsers SET FullName = @FullName, Role = @Role, IsActive = @IsActive,
                PasswordHash = COALESCE(@Hash, PasswordHash)
            WHERE Id = @id
            """, new
        {
            id,
            FullName = req.FullName?.Trim(),
            Role = role,
            req.IsActive,
            Hash = string.IsNullOrEmpty(req.NewPassword) ? null : BCrypt.Net.BCrypt.HashPassword(req.NewPassword),
        });
        if (affected == 0) throw new AppException("Không tìm thấy tài khoản.", 404);
        return await GetAsync(id);
    }

    public async Task DeleteAsync(int id, int currentUserId)
    {
        if (id == currentUserId) throw new AppException("Không thể xóa chính tài khoản của bạn.");
        await using var cnn = await db.OpenAsync();
        await cnn.ExecuteAsync("DELETE FROM dbo.AppUsers WHERE Id = @id", new { id });
    }

    public async Task ChangePasswordAsync(int id, ChangePasswordRequest req)
    {
        ValidatePassword(req.NewPassword);
        await using var cnn = await db.OpenAsync();
        var hash = await cnn.ExecuteScalarAsync<string?>("SELECT PasswordHash FROM dbo.AppUsers WHERE Id = @id", new { id });
        if (hash == null || !BCrypt.Net.BCrypt.Verify(req.CurrentPassword, hash))
            throw new AppException("Mật khẩu hiện tại không đúng.");
        await cnn.ExecuteAsync("UPDATE dbo.AppUsers SET PasswordHash = @h WHERE Id = @id",
            new { id, h = BCrypt.Net.BCrypt.HashPassword(req.NewPassword) });
    }

    private static void ValidateCredentials(string username, string password)
    {
        if (string.IsNullOrWhiteSpace(username) || username.Trim().Length < 3)
            throw new AppException("Tên đăng nhập tối thiểu 3 ký tự.");
        ValidatePassword(password);
    }

    private static void ValidatePassword(string password)
    {
        if (string.IsNullOrEmpty(password) || password.Length < 6)
            throw new AppException("Mật khẩu tối thiểu 6 ký tự.");
    }

    private LoginResponse IssueToken(UserDto user)
    {
        var expires = DateTime.UtcNow.AddHours(_jwt.ExpireHours);
        var claims = new[]
        {
            new Claim(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
            new Claim(ClaimTypes.NameIdentifier, user.Id.ToString()),
            new Claim(ClaimTypes.Name, user.Username),
            new Claim(ClaimTypes.Role, user.Role),
        };
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_jwt.SigningKey));
        var token = new JwtSecurityToken(_jwt.Issuer, _jwt.Audience, claims, expires: expires,
            signingCredentials: new SigningCredentials(key, SecurityAlgorithms.HmacSha256));
        return new LoginResponse(new JwtSecurityTokenHandler().WriteToken(token), expires, user);
    }
}
