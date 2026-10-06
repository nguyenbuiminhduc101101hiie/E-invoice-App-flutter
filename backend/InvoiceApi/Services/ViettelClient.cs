using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using InvoiceApi.Infrastructure;
using Microsoft.Extensions.Options;

namespace InvoiceApi.Services;

/// <summary>Gọi API Viettel vInvoice. Token được cache dùng chung cho mọi người dùng.</summary>
public partial class ViettelClient(IHttpClientFactory httpFactory, IOptions<ViettelOptions> options, ILogger<ViettelClient> logger)
{
    public const string HttpClientName = "viettel";

    private const string ServicesPrefix = "/services/einvoiceapplication/api/InvoiceAPI";

    private static readonly SemaphoreSlim TokenLock = new(1, 1);
    private static string? _cachedToken;
    private static DateTime _tokenExpiresAt = DateTime.MinValue;

    private readonly ViettelOptions _opt = options.Value;

    private HttpClient Http => httpFactory.CreateClient(HttpClientName);

    public async Task<string> GetTokenAsync(bool forceRefresh = false)
    {
        await TokenLock.WaitAsync();
        try
        {
            if (!forceRefresh && _cachedToken != null && DateTime.UtcNow < _tokenExpiresAt)
                return _cachedToken;

            var body = JsonSerializer.Serialize(new { username = _opt.Username, password = _opt.Password });
            using var resp = await Http.PostAsync(_opt.ApiLink + "/auth/login",
                new StringContent(body, Encoding.UTF8, "application/json"));
            var text = await resp.Content.ReadAsStringAsync();

            string? token = null;
            int expiresIn = 0;
            try
            {
                var json = JsonNode.Parse(text);
                token = json?["access_token"]?.ToString();
                int.TryParse(json?["expires_in"]?.ToString(), out expiresIn);
            }
            catch (JsonException) { }

            if (string.IsNullOrEmpty(token))
            {
                logger.LogError("Viettel login failed: {Status} {Body}", resp.StatusCode, text);
                throw new AppException("Có lỗi xảy ra khi lấy token Viettel: " + Truncate(text), 502);
            }

            // Viettel trả expires_in theo giây; trừ hao 2 phút. Không rõ thì cache 10 phút.
            var lifetime = expiresIn > 180 ? TimeSpan.FromSeconds(expiresIn - 120) : TimeSpan.FromMinutes(10);
            _cachedToken = "access_token=" + token;
            _tokenExpiresAt = DateTime.UtcNow.Add(lifetime);
            return _cachedToken;
        }
        finally
        {
            TokenLock.Release();
        }
    }

    /// <summary>Gửi request có kèm cookie token. Trả về nội dung phản hồi kể cả khi lỗi HTTP (giống bản WinForms).</summary>
    private async Task<string> SendAsync(HttpMethod method, string path, Func<HttpContent?> content)
    {
        for (var attempt = 0; attempt < 2; attempt++)
        {
            var token = await GetTokenAsync(forceRefresh: attempt > 0);
            using var req = new HttpRequestMessage(method, _opt.ApiLink + path) { Content = content() };
            req.Headers.TryAddWithoutValidation("Cookie", token);
            using var resp = await Http.SendAsync(req);
            var text = await resp.Content.ReadAsStringAsync();
            if (resp.StatusCode == HttpStatusCode.Unauthorized && attempt == 0)
                continue;
            if (!resp.IsSuccessStatusCode)
                logger.LogWarning("Viettel {Method} {Path} -> {Status}: {Body}", method, path, (int)resp.StatusCode, Truncate(text));
            return text;
        }
        throw new AppException("Không xác thực được với Viettel.", 502);
    }

    private Task<string> PostJsonAsync(string path, string json) =>
        SendAsync(HttpMethod.Post, path, () => new StringContent(json, Encoding.UTF8, "application/json"));

    private Task<string> PostFormAsync(string path, IDictionary<string, string> form) =>
        SendAsync(HttpMethod.Post, path, () => new FormUrlEncodedContent(form));

    public Task<string> CreateInvoiceAsync(string taxCode, string requestJson) =>
        PostJsonAsync($"{ServicesPrefix}/InvoiceWS/createInvoice/{Uri.EscapeDataString(taxCode)}", requestJson);

    public Task<string> CreateInvoiceDraftPreviewAsync(string taxCode, string requestJson) =>
        PostJsonAsync($"{ServicesPrefix}/InvoiceUtilsWS/createInvoiceDraftPreview/{Uri.EscapeDataString(taxCode)}", requestJson);

    public async Task<(string FileName, byte[] Bytes)> GetInvoicePdfAsync(string taxCode, string invoiceNo, string templateCode)
    {
        var request = JsonSerializer.Serialize(new
        {
            supplierTaxCode = taxCode,
            invoiceNo = invoiceNo.Replace("\"", ""),
            templateCode,
            fileType = "PDF"
        });
        var text = await PostJsonAsync($"{ServicesPrefix}/InvoiceUtilsWS/getInvoiceRepresentationFile", request);

        JsonNode? json;
        try { json = JsonNode.Parse(text); }
        catch (JsonException) { throw new AppException("Phản hồi PDF không hợp lệ: " + Truncate(text), 502); }

        var base64 = json?["fileToBytes"]?.ToString();
        if (string.IsNullOrEmpty(base64))
        {
            var desc = json?["description"]?.ToString() ?? Truncate(text);
            throw new AppException("Không tải được PDF hóa đơn: " + desc, 502);
        }
        var fileName = json?["fileName"]?.ToString();
        if (string.IsNullOrWhiteSpace(fileName)) fileName = invoiceNo + ".pdf";
        if (!fileName.EndsWith(".pdf", StringComparison.OrdinalIgnoreCase)) fileName += ".pdf";
        return (fileName, Convert.FromBase64String(base64));
    }

    public Task<string> CancelInvoiceAsync(IDictionary<string, string> form) =>
        PostFormAsync($"{ServicesPrefix}/InvoiceWS/cancelTransactionInvoice", form);

    public Task<string> UpdatePaymentStatusAsync(IDictionary<string, string> form) =>
        PostFormAsync($"{ServicesPrefix}/InvoiceWS/updatePaymentStatus", form);

    /// <summary>Lấy danh sách hóa đơn: thử lần lượt các endpoint như bản WinForms.</summary>
    public async Task<(string Endpoint, string Body)> GetInvoiceListAsync(string taxCode, DateTime from, DateTime to)
    {
        var request = JsonSerializer.Serialize(new
        {
            supplierTaxCode = taxCode,
            fromDate = from.ToString("dd/MM/yyyy"),
            toDate = to.ToString("dd/MM/yyyy")
        });

        (string Path, HttpMethod Method)[] candidates =
        [
            ($"{ServicesPrefix}/InvoiceWS/getInvoiceList", HttpMethod.Get),
            ("/api/InvoiceAPI/InvoiceWS/getInvoiceList", HttpMethod.Get),
            ($"{ServicesPrefix}/InvoiceUtilsWS/getListInvoiceDataControl", HttpMethod.Post),
            ("/api/InvoiceAPI/InvoiceUtilsWS/getListInvoiceDataControl", HttpMethod.Post),
        ];

        Exception? last = null;
        foreach (var (path, method) in candidates)
        {
            try
            {
                var body = await SendAsync(method, path, () =>
                    method == HttpMethod.Get ? null : new StringContent(request, Encoding.UTF8, "application/json"));
                if (!IsInvalidInvoiceListResponse(body))
                    return ($"{method} {path}", body);
            }
            catch (Exception ex) when (ex is not AppException)
            {
                last = ex;
            }
        }

        throw new AppException("Không gọi được API danh sách hóa đơn. Vui lòng kiểm tra endpoint Viettel cấu hình cho tenant này."
                               + (last != null ? " Chi tiết: " + last.Message : ""), 502);
    }

    private static bool IsInvalidInvoiceListResponse(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return true;
        var normalized = text.TrimStart();
        return normalized.StartsWith("<!doctype", StringComparison.OrdinalIgnoreCase)
               || normalized.StartsWith("<html", StringComparison.OrdinalIgnoreCase)
               || InvalidListPattern().IsMatch(text);
    }

    [System.Text.RegularExpressions.GeneratedRegex("\"status\"\\s*:\\s*40[45]\\b|\"(error|message)\"\\s*:\\s*\"Not Found\"|\"title\"\\s*:\\s*\"Method Not Allowed\"|\"message\"\\s*:\\s*\"error\\.http\\.405\"")]
    private static partial System.Text.RegularExpressions.Regex InvalidListPattern();

    public static bool IsNoDataResponse(string text) =>
        text.Contains("\"message\":\"NOT_FOUND_DATA\"") || text.Contains("Không tìm thấy bản ghi");

    public static string Truncate(string? text, int max = 500) =>
        string.IsNullOrEmpty(text) ? "" : text.Length <= max ? text : text[..max] + "…";
}
