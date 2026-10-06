namespace InvoiceApi.Infrastructure;

public class ViettelOptions
{
    public string ApiLink { get; set; } = "https://api-vinvoice.viettel.vn";
    public string Username { get; set; } = "";
    public string Password { get; set; } = "";
    public bool UseProxy { get; set; }
    public string? ProxyHost { get; set; }
    public int ProxyPort { get; set; }
    public int TimeoutSeconds { get; set; } = 60;
}

public class InvoiceDefaultsOptions
{
    public string TaxCode { get; set; } = "";
    public string TemplateCode { get; set; } = "1/001";
    public string InvoiceSeries { get; set; } = "";
    public string PaymentMethod { get; set; } = "TM/CK";
}

public class JwtOptions
{
    public string Issuer { get; set; } = "InvoiceApi";
    public string Audience { get; set; } = "InvoiceApp";
    public string SigningKey { get; set; } = "";
    public int ExpireHours { get; set; } = 12;
}

public class SmtpOptions
{
    public string Server { get; set; } = "";
    public int Port { get; set; } = 587;
    public string User { get; set; } = "";
    public string Password { get; set; } = "";
    public string? FromEmail { get; set; }
    public bool EnableSsl { get; set; } = true;
    public bool AcceptAnyCertificate { get; set; }
}
