using System.Net;
using System.Net.Mail;
using InvoiceApi.Infrastructure;
using Microsoft.Extensions.Options;

namespace InvoiceApi.Services;

public class EmailService(IOptions<SmtpOptions> options)
{
    private readonly SmtpOptions _opt = options.Value;

    public async Task SendInvoiceAsync(string toEmail, string customerName, string invoiceNo, string fileName, byte[] pdf)
    {
        if (string.IsNullOrEmpty(_opt.User) || string.IsNullOrEmpty(_opt.Password) || string.IsNullOrEmpty(_opt.Server))
            throw new AppException("Chưa cấu hình SMTP để gửi email (mục Smtp trong appsettings).");

        using var mail = new MailMessage
        {
            From = new MailAddress(string.IsNullOrWhiteSpace(_opt.FromEmail) ? _opt.User : _opt.FromEmail),
            Subject = $"Hóa đơn điện tử - {invoiceNo}",
            Body = $"Kính gửi {customerName},\n\nChúng tôi gửi kèm hóa đơn điện tử số {invoiceNo}.\n\nTrân trọng cảm ơn!",
            IsBodyHtml = false,
        };
        mail.To.Add(toEmail);
        mail.Attachments.Add(new Attachment(new MemoryStream(pdf), fileName, "application/pdf"));

        using var smtp = new SmtpClient(_opt.Server, _opt.Port)
        {
            Credentials = new NetworkCredential(_opt.User, _opt.Password),
            EnableSsl = _opt.EnableSsl,
        };

        if (_opt.AcceptAnyCertificate)
        {
            // Bản WinForms bỏ qua kiểm tra chứng chỉ SMTP; chỉ bật khi server mail dùng chứng chỉ tự ký
            ServicePointManager.ServerCertificateValidationCallback = (_, _, _, _) => true;
        }

        await smtp.SendMailAsync(mail);
    }
}
