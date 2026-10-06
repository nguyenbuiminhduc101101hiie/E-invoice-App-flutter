using System.Security.Claims;
using InvoiceApi.Models;
using InvoiceApi.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace InvoiceApi.Controllers;

[ApiController]
[Route("api/auth")]
public class AuthController(UserService users) : ControllerBase
{
    [AllowAnonymous]
    [HttpGet("setup-status")]
    public async Task<object> SetupStatus() => new { needsSetup = await users.NeedsSetupAsync() };

    /// <summary>Tạo tài khoản Admin đầu tiên — chỉ dùng được khi bảng AppUsers còn trống.</summary>
    [AllowAnonymous]
    [HttpPost("setup")]
    public Task<LoginResponse> Setup(SetupRequest req) => users.SetupFirstAdminAsync(req);

    [AllowAnonymous]
    [HttpPost("login")]
    public Task<LoginResponse> Login(LoginRequest req) => users.LoginAsync(req);

    [Authorize]
    [HttpGet("me")]
    public Task<UserDto> Me() => users.GetAsync(User.GetUserId());

    [Authorize]
    [HttpPost("change-password")]
    public async Task<IActionResult> ChangePassword(ChangePasswordRequest req)
    {
        await users.ChangePasswordAsync(User.GetUserId(), req);
        return NoContent();
    }
}

public static class ClaimsExtensions
{
    public static int GetUserId(this ClaimsPrincipal user) =>
        int.Parse(user.FindFirstValue(ClaimTypes.NameIdentifier) ?? "0");
}
