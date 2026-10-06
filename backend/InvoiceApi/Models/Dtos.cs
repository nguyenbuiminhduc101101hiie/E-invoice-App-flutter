namespace InvoiceApi.Models;

// ---------- Auth & Users ----------
public record LoginRequest(string Username, string Password);
public record SetupRequest(string Username, string Password, string? FullName);
public record ChangePasswordRequest(string CurrentPassword, string NewPassword);
public record UserDto(int Id, string Username, string? FullName, string Role, bool IsActive, DateTime CreatedAt, DateTime? LastLoginAt);
public record LoginResponse(string Token, DateTime ExpiresAt, UserDto User);
public record CreateUserRequest(string Username, string Password, string? FullName, string Role);
public record UpdateUserRequest(string? FullName, string Role, bool IsActive, string? NewPassword);

// ---------- Lookups ----------
public record NamedItem(string Id, string Name);
public record ServiceItem(string Id, string Name, string? Code, string? Unit, double Production, double TaxPercent);
public record InvoiceDefaults(string TaxCode, string TemplateCode, string InvoiceSeries);

// ---------- Orders ----------
public class OrderSearchQuery
{
    public DateTime From { get; set; } = DateTime.Today;
    public DateTime To { get; set; } = DateTime.Today;
    public string? CustomerName { get; set; }
    public string? EmployeeName { get; set; }
    public string? CustomerPhone { get; set; }
    public bool ByPaymentDate { get; set; }
}

public class OrderItemDto
{
    public string ServiceId { get; set; } = "";
    public string ServiceName { get; set; } = "";
    public int Quantity { get; set; }
    public int PromotionQuantity { get; set; }
    public double UnitPrice { get; set; }
    public int ActualQuantity => Quantity - PromotionQuantity;
    public double Total => ActualQuantity * UnitPrice;
}

public class OrderListItemDto
{
    public string Id { get; set; } = "";
    public string CustomerName { get; set; } = "";
    public string? ShopName { get; set; }
    public string? CustomerPhone { get; set; }
    public string? CustomerAddress { get; set; }
    public string? EmployeeNames { get; set; }
    public List<OrderItemDto> Items { get; set; } = [];
    public double TotalPrice { get; set; }
    public double CashAmount { get; set; }
    public double TransferAmount { get; set; }
    public DateTime? CreatedAt { get; set; }
    public string? PaymentStatus { get; set; }
    public string? DeliveryStatus { get; set; }
    public bool IsDraft { get; set; }
    public string? InvoiceNoViettel { get; set; }
    public string? DateInvViettel { get; set; }
    public bool Exported { get; set; }
    public string? HoaDonNoiBo { get; set; }
    public string? TemplateCode { get; set; }
    public bool IsConvertToLiter { get; set; }
    public string? TaxCode { get; set; }
    public string? Identification { get; set; }
    public string? PersonalName { get; set; }
    public string? InvoiceName { get; set; }
    public string? InvoiceAddress { get; set; }
    public string? PaymentHistory { get; set; }
}

public class OrderDetailDto
{
    public string Id { get; set; } = "";
    public string CustomerName { get; set; } = "";
    public string CustomerPhone { get; set; } = "";
    public string CustomerAddress { get; set; } = "";
    public double TaxPercent { get; set; }
    public bool IsConvertToLiter { get; set; }
    /// <summary>Số item vừa được tự động quy đổi sang Lít khi mở (chưa lưu DB).</summary>
    public int AutoConvertedCount { get; set; }
    public List<OrderItemDto> Items { get; set; } = [];
}

public class SaveOrderRequest
{
    public string CustomerName { get; set; } = "";
    public string CustomerPhone { get; set; } = "";
    public string CustomerAddress { get; set; } = "";
    public double TaxPercent { get; set; }
    public bool IsConvertToLiter { get; set; }
    public List<OrderItemDto> Items { get; set; } = [];
}

// ---------- Invoices ----------
public class InvoiceHeaderRequest
{
    public List<string> OrderIds { get; set; } = [];
    public string? TaxCode { get; set; }
    public string? TemplateCode { get; set; }
    public string? InvoiceSeries { get; set; }
}

public class InvoiceLinePreview
{
    public int LineNumber { get; set; }
    public string ItemCode { get; set; } = "";
    public string ItemName { get; set; } = "";
    public string UnitName { get; set; } = "";
    public double UnitPrice { get; set; }
    public int Quantity { get; set; }
    public double AmountWithoutTax { get; set; }
    public double TaxPercent { get; set; }
    public double TaxAmount { get; set; }
    public double Discount { get; set; }
}

public class InvoiceGroupPreview
{
    public double TaxPercent { get; set; }
    public double TotalWithoutTax { get; set; }
    public double TotalTax { get; set; }
    public double TotalWithTax { get; set; }
    public double DiscountAmount { get; set; }
    public string AmountInWords { get; set; } = "";
    public List<InvoiceLinePreview> Lines { get; set; } = [];
    public string RequestJson { get; set; } = "";
}

public class BuyerPreview
{
    public string Kind { get; set; } = ""; // company | personal | consumer | unknown
    public string? BuyerName { get; set; }
    public string? BuyerLegalName { get; set; }
    public string? TaxCode { get; set; }
    public string? IdNo { get; set; }
    public string? Address { get; set; }
    public string? Phone { get; set; }
}

public class InvoicePreviewResponse
{
    public BuyerPreview Buyer { get; set; } = new();
    public List<InvoiceGroupPreview> Groups { get; set; } = [];
    public List<string> Warnings { get; set; } = [];
    public int OrdersToConvert { get; set; }
}

public class CreateInvoiceResponse
{
    public List<string> InvoiceNos { get; set; } = [];
    public int ConvertedOrders { get; set; }
    public List<string> Warnings { get; set; } = [];
    public string? Error { get; set; }
}

public class DraftCustomerGroup
{
    public string CustomerName { get; set; } = "";
    public string CustomerPhone { get; set; } = "";
    public List<string> OrderIds { get; set; } = [];
    public List<double> TaxPercents { get; set; } = [];
    public string SuggestedInvoiceNo { get; set; } = "";
}

public class DraftPrepareResponse
{
    public List<DraftCustomerGroup> Groups { get; set; } = [];
    public List<string> Warnings { get; set; } = [];
}

public class DraftGroupRequest
{
    public List<string> OrderIds { get; set; } = [];
    public string InvoiceNo { get; set; } = "";
}

public class CreateDraftRequest
{
    public string? TaxCode { get; set; }
    public string? TemplateCode { get; set; }
    public string? InvoiceSeries { get; set; }
    public List<DraftGroupRequest> Groups { get; set; } = [];
}

public class DraftFileResult
{
    public string InvoiceNo { get; set; } = "";
    public double TaxPercent { get; set; }
    public string? FileId { get; set; }
    public string? FileName { get; set; }
}

public class DraftGroupResult
{
    public string InvoiceNo { get; set; } = "";
    public bool Success { get; set; }
    public string? Error { get; set; }
    public List<DraftFileResult> Files { get; set; } = [];
}

public class CreateDraftResponse
{
    public int ConvertedOrders { get; set; }
    public List<DraftGroupResult> Groups { get; set; } = [];
}

public class SendEmailRequest
{
    public string InvoiceNo { get; set; } = "";
    public string? TemplateCode { get; set; }
    public string? TaxCode { get; set; }
    public string? CustomerPhone { get; set; }
    public string? CustomerName { get; set; }
    public string? ToEmail { get; set; }
}

public class CancelInvoiceRequest
{
    public string? TaxCode { get; set; }
    public string InvoiceNo { get; set; } = "";
    public string StrIssueDate { get; set; } = "";
    public string AdditionalReferenceDesc { get; set; } = "";
    public string? AdditionalReferenceDate { get; set; }
}

public class UpdatePaymentStatusRequest
{
    public string? TaxCode { get; set; }
    public string InvoiceNo { get; set; } = "";
    public string StrIssueDate { get; set; } = "";
    public string? TemplateCode { get; set; }
    public string? BuyerEmailAddress { get; set; }
    public string PaymentType { get; set; } = "TM/CK";
    public bool CusGetInvoiceRight { get; set; } = true;
}
