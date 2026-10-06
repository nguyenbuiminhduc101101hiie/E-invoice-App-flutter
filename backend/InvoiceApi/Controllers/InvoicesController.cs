using System.Text.Json.Nodes;
using InvoiceApi.Infrastructure;
using InvoiceApi.Models;
using InvoiceApi.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace InvoiceApi.Controllers;

[ApiController]
[Route("api/invoices")]
[Authorize]
public class InvoicesController(InvoiceService invoices, DraftFileStore draftFiles) : ControllerBase
{
    /// <summary>Xem trước hóa đơn (đã tách theo VAT) trước khi lập.</summary>
    [HttpPost("preview")]
    public Task<InvoicePreviewResponse> Preview(InvoiceHeaderRequest req) => invoices.PreviewAsync(req);

    /// <summary>Lập hóa đơn trên Viettel.</summary>
    [HttpPost]
    public Task<CreateInvoiceResponse> Create(InvoiceHeaderRequest req) => invoices.CreateAsync(req);

    /// <summary>Chuẩn bị lập nháp: nhóm theo khách hàng và gợi ý số hóa đơn nội bộ.</summary>
    [HttpPost("drafts/prepare")]
    public Task<DraftPrepareResponse> PrepareDraft(InvoiceHeaderRequest req) => invoices.PrepareDraftAsync(req);

    [HttpPost("drafts")]
    public Task<CreateDraftResponse> CreateDraft(CreateDraftRequest req) => invoices.CreateDraftAsync(req);

    [HttpGet("drafts/files/{id}")]
    public IActionResult DraftFile(string id)
    {
        var file = draftFiles.Find(id) ?? throw new AppException("Không tìm thấy file PDF nháp.", 404);
        return PhysicalFile(file.Path, "application/pdf", file.FileName);
    }

    /// <summary>Tải PDF hóa đơn thật từ Viettel.</summary>
    [HttpGet("pdf")]
    public async Task<IActionResult> Pdf([FromQuery] string invoiceNo, [FromQuery] string? templateCode, [FromQuery] string? taxCode)
    {
        var (fileName, bytes) = await invoices.GetPdfAsync(invoiceNo, templateCode, taxCode);
        return File(bytes, "application/pdf", fileName);
    }

    [HttpPost("email")]
    public async Task<object> SendEmail(SendEmailRequest req) => new { sentTo = await invoices.SendEmailAsync(req) };

    /// <summary>Danh sách hóa đơn trên hệ thống Viettel (GetInvoiceList).</summary>
    [HttpGet("viettel")]
    public Task<JsonNode> ViettelList([FromQuery] DateTime from, [FromQuery] DateTime to, [FromQuery] string? taxCode) =>
        invoices.GetViettelInvoiceListAsync(from, to, taxCode);

    [Authorize(Roles = Roles.Admin)]
    [HttpPost("viettel/cancel")]
    public async Task<object> Cancel(CancelInvoiceRequest req) => new { result = await invoices.CancelInvoiceAsync(req) };

    [Authorize(Roles = Roles.Admin)]
    [HttpPost("viettel/payment-status")]
    public async Task<object> UpdatePaymentStatus(UpdatePaymentStatusRequest req) =>
        new { result = await invoices.UpdatePaymentStatusAsync(req) };
}
