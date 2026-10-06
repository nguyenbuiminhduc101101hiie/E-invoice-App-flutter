using InvoiceApi.Models;
using InvoiceApi.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace InvoiceApi.Controllers;

[ApiController]
[Route("api/orders")]
[Authorize]
public class OrdersController(OrderService orders) : ControllerBase
{
    [HttpGet]
    public Task<List<OrderListItemDto>> Search([FromQuery] OrderSearchQuery query) => orders.SearchAsync(query);

    [HttpGet("{id}")]
    public Task<OrderDetailDto> Get(string id) => orders.GetDetailAsync(id);

    [HttpPut("{id}")]
    public async Task<IActionResult> Save(string id, SaveOrderRequest req)
    {
        await orders.SaveAsync(id, req);
        return NoContent();
    }
}
