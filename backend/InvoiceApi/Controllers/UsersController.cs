using InvoiceApi.Models;
using InvoiceApi.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace InvoiceApi.Controllers;

[ApiController]
[Route("api/users")]
[Authorize(Roles = Roles.Admin)]
public class UsersController(UserService users) : ControllerBase
{
    [HttpGet]
    public Task<List<UserDto>> List() => users.ListAsync();

    [HttpPost]
    public Task<UserDto> Create(CreateUserRequest req) => users.CreateAsync(req);

    [HttpPut("{id:int}")]
    public Task<UserDto> Update(int id, UpdateUserRequest req) => users.UpdateAsync(id, req, User.GetUserId());

    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id)
    {
        await users.DeleteAsync(id, User.GetUserId());
        return NoContent();
    }
}
