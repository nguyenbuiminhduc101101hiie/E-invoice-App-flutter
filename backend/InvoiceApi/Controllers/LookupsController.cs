using InvoiceApi.Infrastructure;
using InvoiceApi.Models;
using InvoiceApi.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace InvoiceApi.Controllers;

[ApiController]
[Route("api/lookups")]
[Authorize]
public class LookupsController(Db db, OrderService orders, InvoiceService invoices) : ControllerBase
{
    [HttpGet("customers")]
    public async Task<List<NamedItem>> Customers()
    {
        var rows = await db.QueryRowsAsync("SELECT * FROM Customers ORDER BY Name");
        return rows.Where(r => r.Str("Name").Length > 0)
            .Select(r => new NamedItem(r.Str("id"), r.Str("Name"))).ToList();
    }

    [HttpGet("employees")]
    public async Task<List<NamedItem>> Employees()
    {
        var rows = await db.QueryRowsAsync("SELECT * FROM Employees ORDER BY Name");
        return rows.Where(r => r.Str("Name").Length > 0)
            .Select(r => new NamedItem(r.Str("id"), r.Str("Name"))).ToList();
    }

    [HttpGet("services")]
    public Task<List<ServiceItem>> Services() => orders.ListServicesAsync();

    [HttpGet("invoice-defaults")]
    public InvoiceDefaults InvoiceDefaults() => invoices.GetDefaults();
}
