using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Dapper;
using InvoiceApi.Infrastructure;
using InvoiceApi.Models;
using Microsoft.Extensions.Options;

namespace InvoiceApi.Services;

public class InvoiceService(
    Db db,
    OrderService orders,
    ViettelClient viettel,
    DraftFileStore draftFiles,
    EmailService email,
    IOptions<InvoiceDefaultsOptions> defaults,
    ILogger<InvoiceService> logger)
{
    // Tránh 2 người cùng lập hóa đơn cho cùng đơn hàng cùng lúc (tạo trùng trên Viettel)
    private static readonly SemaphoreSlim IssueLock = new(1, 1);

    private readonly InvoiceDefaultsOptions _defaults = defaults.Value;

    public InvoiceDefaults GetDefaults() => new(_defaults.TaxCode, _defaults.TemplateCode, _defaults.InvoiceSeries);

    private InvoiceHeader ResolveHeader(string? taxCode, string? templateCode, string? invoiceSeries)
    {
        var header = new InvoiceHeader(
            string.IsNullOrWhiteSpace(taxCode) ? _defaults.TaxCode : taxCode.Trim(),
            string.IsNullOrWhiteSpace(templateCode) ? _defaults.TemplateCode : templateCode.Trim(),
            string.IsNullOrWhiteSpace(invoiceSeries) ? _defaults.InvoiceSeries : invoiceSeries.Trim(),
            _defaults.PaymentMethod);
        if (string.IsNullOrEmpty(header.TaxCode)) throw new AppException("Nhập Tax Code!");
        if (string.IsNullOrEmpty(header.TemplateCode)) throw new AppException("Nhập Mẫu Số!");
        if (string.IsNullOrEmpty(header.InvoiceSeries)) throw new AppException("Nhập INV Series!");
        return header;
    }

    private async Task<List<Row>> LoadSelectedOrdersAsync(List<string> ids)
    {
        if (ids.Count == 0) throw new AppException("Vui lòng chọn ít nhất một đơn hàng!");
        var rows = await orders.LoadOrdersAsync(ids);
        if (rows.Count == 0) throw new AppException("Không tìm thấy đơn hàng đã chọn.", 404);
        // Giữ thứ tự như người dùng chọn
        var order = ids.Select((id, i) => (id, i)).GroupBy(x => x.id, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(g => g.Key, g => g.First().i, StringComparer.OrdinalIgnoreCase);
        return rows.OrderBy(r => order.GetValueOrDefault(r.Str("id"), int.MaxValue)).ToList();
    }

    private static void EnsureNoViettelInvoice(IEnumerable<Row> rows)
    {
        var existing = rows.FirstOrDefault(r => !string.IsNullOrEmpty(r.Str("InvoiceNoViettel")));
        if (existing != null)
            throw new AppException($"Đơn của '{existing.Str("CustomerName")}' đã có Số Hóa Đơn Viettel ({existing.Str("InvoiceNoViettel")}).");
    }

    private async Task<(BuyerData Buyer, List<InvoiceGroupPreview> Groups, List<string> Warnings)> BuildAsync(
        InvoiceHeader header, List<Row> rows, bool applyPendingConversionInMemory)
    {
        var warnings = new List<string>();
        var prepared = rows.Select(r => new OrderForInvoice(r, OrderArraysData.FromRow(r))).ToList();
        var services = await orders.LoadServicesAsync(prepared.SelectMany(p => p.Arrays.ServiceIds));

        if (applyPendingConversionInMemory)
        {
            foreach (var p in prepared.Where(p => !p.Row.Bool("IsConvertToLiter")))
                p.Arrays.ConvertToLiter(services);
        }

        var phone = rows[0].Str("CustomerPhone");
        var customers = await db.QueryRowsAsync("SELECT TOP 1 * FROM Customers WHERE phone = @phone", new { phone });
        var buyer = InvoiceBuilder.BuildBuyer(customers.FirstOrDefault(), warnings);

        var lines = InvoiceBuilder.BuildLines(prepared, services);
        var skipped = prepared.Count(p => p.Arrays.ServiceIds.Count != p.Arrays.Quantities.Count
                                          || p.Arrays.Quantities.Count != p.Arrays.UnitPrices.Count);
        if (skipped > 0) warnings.Add($"{skipped} đơn có dữ liệu item không khớp (số dịch vụ/số lượng/đơn giá) nên bị bỏ qua.");

        var groups = InvoiceBuilder.BuildGroups(header, buyer, lines);
        if (groups.Count > 1)
            warnings.Add($"Đơn có {groups.Count} mức thuế VAT khác nhau. Hệ thống sẽ tạo {groups.Count} hóa đơn riêng trên Viettel.");
        return (buyer, groups, warnings);
    }

    private static BuyerPreview ToPreview(BuyerData b) => new()
    {
        Kind = b.Kind,
        BuyerName = b.BuyerName,
        BuyerLegalName = b.BuyerLegalName,
        TaxCode = b.BuyerTaxCode,
        IdNo = b.BuyerIdNo,
        Address = b.BuyerAddressLine,
        Phone = b.BuyerPhoneNumber,
    };

    // ===================== Lập hóa đơn =====================

    private async Task ValidateForIssueAsync(List<Row> rows, int selectedCount)
    {
        if (rows.Any(r => r.Bool("daxuatthanhcong")))
            throw new AppException("Đã xuất HĐ lên Viettel. Không xuất nữa — nếu chưa thấy E-invoiceNo, liên hệ Admin.");

        var firstHdnb = rows[0].Str("HoaDonNoiBo");
        if (rows.Any(r => r.Str("HoaDonNoiBo") != firstHdnb))
            throw new AppException("Các dòng đã chọn phải có chung Hóa Đơn Nội Bộ!");

        EnsureNoViettelInvoice(rows);

        if (!string.IsNullOrEmpty(firstHdnb))
        {
            await using var cnn = await db.OpenAsync();
            var count = await cnn.ExecuteScalarAsync<int>(
                "SELECT COUNT(*) FROM Orders_viettel WHERE HoaDonNoiBo = @hdnb", new { hdnb = firstHdnb });
            if (count < selectedCount)
                throw new AppException($"Số lượng Hóa Đơn Nội Bộ '{firstHdnb}' trong database ({count}) ít hơn số dòng đã chọn ({selectedCount}). Vui lòng kiểm tra lại!");
        }
    }

    public async Task<InvoicePreviewResponse> PreviewAsync(InvoiceHeaderRequest req)
    {
        var header = ResolveHeader(req.TaxCode, req.TemplateCode, req.InvoiceSeries);
        var rows = await LoadSelectedOrdersAsync(req.OrderIds);
        await ValidateForIssueAsync(rows, req.OrderIds.Distinct().Count());

        var (buyer, groups, warnings) = await BuildAsync(header, rows, applyPendingConversionInMemory: true);
        return new InvoicePreviewResponse
        {
            Buyer = ToPreview(buyer),
            Groups = groups,
            Warnings = warnings,
            OrdersToConvert = rows.Count(r => !r.Bool("IsConvertToLiter")),
        };
    }

    public async Task<CreateInvoiceResponse> CreateAsync(InvoiceHeaderRequest req)
    {
        var header = ResolveHeader(req.TaxCode, req.TemplateCode, req.InvoiceSeries);

        await IssueLock.WaitAsync();
        try
        {
            var rows = await LoadSelectedOrdersAsync(req.OrderIds);
            await ValidateForIssueAsync(rows, req.OrderIds.Distinct().Count());

            var response = new CreateInvoiceResponse
            {
                ConvertedOrders = await orders.ConvertPendingOrdersAsync(rows)
            };

            rows = await LoadSelectedOrdersAsync(req.OrderIds);
            var (_, groups, warnings) = await BuildAsync(header, rows, applyPendingConversionInMemory: false);
            response.Warnings = warnings;
            if (groups.Count == 0) throw new AppException("Không có item hợp lệ để lập hóa đơn.");

            foreach (var group in groups)
            {
                var result = await viettel.CreateInvoiceAsync(header.TaxCode, group.RequestJson);
                var invoiceNo = ExtractInvoiceNo(result);
                if (string.IsNullOrEmpty(invoiceNo))
                {
                    logger.LogError("createInvoice VAT {Tax}% failed: {Result}", group.TaxPercent, result);
                    response.Error = $"Không lấy được số hóa đơn từ kết quả trả về (VAT {group.TaxPercent:G}%): {DescribeError(result)}";
                    break;
                }
                response.InvoiceNos.Add(invoiceNo);
            }

            if (response.InvoiceNos.Count > 0)
            {
                await SaveIssuedInvoiceAsync(rows.Select(r => r.Str("id")).ToList(), response.InvoiceNos, header.TemplateCode, response);
            }
            else if (response.Error != null)
            {
                throw new AppException(response.Error, 502);
            }

            return response;
        }
        finally
        {
            IssueLock.Release();
        }
    }

    private async Task SaveIssuedInvoiceAsync(List<string> ids, List<string> invoiceNos, string templateCode, CreateInvoiceResponse response)
    {
        await using var cnn = await db.OpenAsync();

        // Bước 1: đánh dấu đã xuất ngay để không xuất trùng, kể cả khi bước 2 lỗi
        var affected = await cnn.ExecuteAsync("UPDATE Orders_viettel SET daxuatthanhcong = 1 WHERE id IN @ids", new { ids });
        if (affected == 0)
            response.Warnings.Add("Không có đơn hàng nào được cập nhật daxuatthanhcong = 1.");

        var invoiceInfo = new
        {
            ids,
            DateInvViettel = DateTime.Today.ToString("dd-MMM-yyyy", CultureInfo.InvariantCulture),
            InvoiceNoViettel = string.Join(",", invoiceNos),
            Mauso = templateCode,
        };

        try
        {
            await cnn.ExecuteAsync("""
                UPDATE Orders_viettel
                SET DateInvViettel = @DateInvViettel, InvoiceNoViettel = @InvoiceNoViettel, mauso = @Mauso
                WHERE id IN @ids
                """, invoiceInfo);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Update invoice info failed for {Ids}", ids);
            response.Warnings.Add("Đã cập nhật daxuatthanhcong = 1 nhưng cập nhật thông tin hóa đơn bị lỗi: " + ex.Message);
            return;
        }

        // Cập nhật tương tự cho bảng Orders; lỗi ở đây không ảnh hưởng dữ liệu đã lưu vào Orders_viettel
        try
        {
            await cnn.ExecuteAsync("""
                UPDATE Orders
                SET DateInvViettel = @DateInvViettel, InvoiceNoViettel = @InvoiceNoViettel, mauso = @Mauso
                WHERE id IN @ids
                """, invoiceInfo);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Update Orders invoice info failed for {Ids}", ids);
            response.Warnings.Add("Đã cập nhật Orders_viettel nhưng cập nhật bảng Orders bị lỗi: " + ex.Message);
        }
    }

    // ===================== Hóa đơn nháp =====================

    public async Task<DraftPrepareResponse> PrepareDraftAsync(InvoiceHeaderRequest req)
    {
        var header = ResolveHeader(req.TaxCode, req.TemplateCode, req.InvoiceSeries);
        var rows = await LoadSelectedOrdersAsync(req.OrderIds);
        EnsureNoViettelInvoice(rows);

        var response = new DraftPrepareResponse();
        var customerGroups = rows
            .GroupBy(r => r.Str("CustomerPhone") + "\u001F" + r.Str("CustomerName"))
            .ToList();

        var nextStt = await GetNextInternalSttAsync();
        foreach (var grp in customerGroups)
        {
            var groupRows = grp.ToList();
            var (_, groups, warnings) = await BuildAsync(header, groupRows, applyPendingConversionInMemory: true);
            var customerName = groupRows[0].Str("CustomerName");
            response.Warnings.AddRange(warnings.Select(w => $"{customerName}: {w}"));
            response.Groups.Add(new DraftCustomerGroup
            {
                CustomerName = customerName,
                CustomerPhone = groupRows[0].Str("CustomerPhone"),
                OrderIds = groupRows.Select(r => r.Str("id")).ToList(),
                TaxPercents = groups.Select(g => g.TaxPercent).ToList(),
                SuggestedInvoiceNo = FormatInternalInvoiceNo(nextStt++, customerName),
            });
        }
        return response;
    }

    public async Task<CreateDraftResponse> CreateDraftAsync(CreateDraftRequest req)
    {
        var header = ResolveHeader(req.TaxCode, req.TemplateCode, req.InvoiceSeries);
        if (req.Groups.Count == 0) throw new AppException("Không có nhóm đơn nào để lập nháp.");
        if (req.Groups.Any(g => string.IsNullOrWhiteSpace(g.InvoiceNo)))
            throw new AppException("Vui lòng nhập số hóa đơn nội bộ cho tất cả khách hàng!");

        var response = new CreateDraftResponse();
        foreach (var g in req.Groups)
        {
            var baseNo = g.InvoiceNo.Trim();
            var result = new DraftGroupResult { InvoiceNo = baseNo };
            response.Groups.Add(result);
            try
            {
                var rows = await LoadSelectedOrdersAsync(g.OrderIds);
                EnsureNoViettelInvoice(rows);
                response.ConvertedOrders += await orders.ConvertPendingOrdersAsync(rows);
                rows = await LoadSelectedOrdersAsync(g.OrderIds);

                var (_, groups, _) = await BuildAsync(header, rows, applyPendingConversionInMemory: false);
                if (groups.Count == 0) throw new AppException("Không có item hợp lệ để lập hóa đơn nháp.");

                var draftNos = new List<string>();
                foreach (var group in groups)
                {
                    var invoiceNo = groups.Count > 1
                        ? baseNo + "_VAT" + group.TaxPercent.ToString("G", CultureInfo.InvariantCulture)
                        : baseNo;

                    var apiResult = await viettel.CreateInvoiceDraftPreviewAsync(header.TaxCode, group.RequestJson);
                    var pdfBase64 = ExtractDraftPdfBase64(apiResult)
                        ?? throw new AppException($"Lỗi lưu PDF (VAT {group.TaxPercent:G}%): {DescribeError(apiResult)}", 502);

                    var (fileId, fileName) = await draftFiles.SaveAsync(invoiceNo, Convert.FromBase64String(pdfBase64));
                    result.Files.Add(new DraftFileResult { InvoiceNo = invoiceNo, TaxPercent = group.TaxPercent, FileId = fileId, FileName = fileName });
                    draftNos.Add(invoiceNo);
                }

                var combined = string.Join(",", draftNos);
                var ids = rows.Select(r => r.Str("id")).ToList();
                await using var cnn = await db.OpenAsync();
                await cnn.ExecuteAsync("UPDATE Orders_viettel SET IsDraft = 1, hoadonnoibo = @combined WHERE id IN @ids", new { combined, ids });
                await cnn.ExecuteAsync("UPDATE Orders SET IsDraft = 1, hoadonnoibo = @combined WHERE id IN @ids", new { combined, ids });

                result.InvoiceNo = combined;
                result.Success = true;
            }
            catch (AppException ex)
            {
                result.Error = ex.Message;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Create draft failed for {InvoiceNo}", baseNo);
                result.Error = ex.Message;
            }
        }
        return response;
    }

    private async Task<int> GetNextInternalSttAsync()
    {
        // Số HĐ nội bộ dạng yyMMdd_STT_TenKhach, STT tăng dần trong tháng
        var monthPrefix = DateTime.Now.ToString("yyMM");
        await using var cnn = await db.OpenAsync();
        var existing = await cnn.QueryAsync<string>(
            "SELECT HoaDonNoiBo FROM orders WHERE HoaDonNoiBo IS NOT NULL AND HoaDonNoiBo LIKE @prefix",
            new { prefix = monthPrefix + "%" });

        var pattern = new Regex("^" + Regex.Escape(monthPrefix) + @"\d{2}_(\d+)_");
        var maxStt = 0;
        foreach (var value in existing)
        {
            // Một đơn có thể chứa nhiều số nháp nối bằng dấu phẩy (tách theo VAT)
            foreach (var part in (value ?? "").Split(','))
            {
                var m = pattern.Match(part.Trim());
                if (m.Success && int.TryParse(m.Groups[1].Value, out var stt) && stt > maxStt) maxStt = stt;
            }
        }
        return maxStt + 1;
    }

    private static string FormatInternalInvoiceNo(int stt, string customerName)
    {
        var safe = DraftFileStore.SanitizeFileName(customerName ?? "")
            .Replace('(', '_').Replace(')', '_').Replace('%', '_').Trim();
        if (string.IsNullOrEmpty(safe) || safe == "invoice") safe = "Customer";
        return DateTime.Now.ToString("yyMMdd") + "_" + stt + "_" + safe;
    }

    // ===================== PDF / Email / Viettel tools =====================

    public Task<(string FileName, byte[] Bytes)> GetPdfAsync(string invoiceNo, string? templateCode, string? taxCode)
    {
        if (string.IsNullOrWhiteSpace(invoiceNo)) throw new AppException("Đơn chưa có số hóa đơn Viettel.");
        return viettel.GetInvoicePdfAsync(
            string.IsNullOrWhiteSpace(taxCode) ? _defaults.TaxCode : taxCode.Trim(),
            invoiceNo.Trim(),
            string.IsNullOrWhiteSpace(templateCode) ? _defaults.TemplateCode : templateCode.Trim());
    }

    public async Task<string> SendEmailAsync(SendEmailRequest req)
    {
        var to = req.ToEmail?.Trim();
        if (string.IsNullOrEmpty(to))
        {
            await using var cnn = await db.OpenAsync();
            if (!string.IsNullOrWhiteSpace(req.CustomerPhone))
                to = await cnn.ExecuteScalarAsync<string?>(
                    "SELECT TOP 1 Email FROM Customers WHERE phone = @phone AND Email IS NOT NULL AND Email != ''",
                    new { phone = req.CustomerPhone.Trim() });
            else if (!string.IsNullOrWhiteSpace(req.CustomerName))
                to = await cnn.ExecuteScalarAsync<string?>(
                    "SELECT TOP 1 Email FROM Customers WHERE Name = @name AND Email IS NOT NULL AND Email != ''",
                    new { name = req.CustomerName.Trim() });
        }
        if (string.IsNullOrWhiteSpace(to)) throw new AppException("Khách hàng chưa có email. Vui lòng nhập email người nhận.");

        var (fileName, bytes) = await GetPdfAsync(req.InvoiceNo, req.TemplateCode, req.TaxCode);
        await email.SendInvoiceAsync(to.Trim(), req.CustomerName ?? "Quý khách", req.InvoiceNo, fileName, bytes);
        return to.Trim();
    }

    public async Task<JsonNode> GetViettelInvoiceListAsync(DateTime from, DateTime to, string? taxCode)
    {
        var tax = string.IsNullOrWhiteSpace(taxCode) ? _defaults.TaxCode : taxCode.Trim();
        if (string.IsNullOrEmpty(tax)) throw new AppException("Thiếu Tax Code.");

        var (endpoint, body) = await viettel.GetInvoiceListAsync(tax, from, to);
        var result = new JsonObject { ["endpoint"] = endpoint };

        if (ViettelClient.IsNoDataResponse(body))
        {
            result["rows"] = new JsonArray();
            result["message"] = "Không tìm thấy dữ liệu hóa đơn theo điều kiện lọc hiện tại.";
            return result;
        }

        JsonNode? root = null;
        try { root = JsonNode.Parse(body); } catch (JsonException) { }
        var array = FindFirstObjectArray(root);
        if (array == null)
        {
            result["rows"] = new JsonArray();
            result["raw"] = body;
            return result;
        }
        result["rows"] = array.DeepClone();
        return result;
    }

    public async Task<string> CancelInvoiceAsync(CancelInvoiceRequest req)
    {
        var form = new Dictionary<string, string>
        {
            ["supplierTaxCode"] = string.IsNullOrWhiteSpace(req.TaxCode) ? _defaults.TaxCode : req.TaxCode.Trim(),
            ["invoiceNo"] = req.InvoiceNo.Trim(),
            ["strIssueDate"] = req.StrIssueDate.Trim(),
            ["additionalReferenceDesc"] = req.AdditionalReferenceDesc.Trim(),
            ["additionalReferenceDate"] = string.IsNullOrWhiteSpace(req.AdditionalReferenceDate)
                ? DateTimeOffset.UtcNow.ToUnixTimeMilliseconds().ToString()
                : req.AdditionalReferenceDate.Trim(),
        };
        if (form["invoiceNo"].Length == 0 || form["strIssueDate"].Length == 0)
            throw new AppException("Cần nhập số hóa đơn và ngày lập (strIssueDate).");
        return await viettel.CancelInvoiceAsync(form);
    }

    public async Task<string> UpdatePaymentStatusAsync(UpdatePaymentStatusRequest req)
    {
        var form = new Dictionary<string, string>
        {
            ["supplierTaxCode"] = string.IsNullOrWhiteSpace(req.TaxCode) ? _defaults.TaxCode : req.TaxCode.Trim(),
            ["invoiceNo"] = req.InvoiceNo.Trim(),
            ["strIssueDate"] = req.StrIssueDate.Trim(),
            ["templateCode"] = string.IsNullOrWhiteSpace(req.TemplateCode) ? _defaults.TemplateCode : req.TemplateCode.Trim(),
            ["buyerEmailAddress"] = req.BuyerEmailAddress?.Trim() ?? "",
            ["paymentType"] = req.PaymentType,
            ["paymentTypeName"] = req.PaymentType,
            ["cusGetInvoiceRight"] = req.CusGetInvoiceRight ? "true" : "false",
        };
        if (form["invoiceNo"].Length == 0 || form["strIssueDate"].Length == 0)
            throw new AppException("Cần nhập số hóa đơn và ngày lập (strIssueDate).");
        return await viettel.UpdatePaymentStatusAsync(form);
    }

    // ===================== Parse phản hồi Viettel =====================

    public static string? ExtractInvoiceNo(string result)
    {
        try
        {
            var found = FindProperty(JsonNode.Parse(result), "invoiceNo");
            if (!string.IsNullOrWhiteSpace(found)) return found.Trim();
        }
        catch (JsonException) { }

        // Fallback giống bản cũ: tìm đoạn chứa "invoiceNo" trong chuỗi
        foreach (var part in result.Split(','))
        {
            if (!part.Contains("invoiceNo")) continue;
            var pieces = part.Split(':');
            if (pieces.Length < 2) continue;
            var value = pieces[1].Replace("\"", "").Replace("}", "").Trim();
            if (value.Length > 0 && value != "null") return value;
        }
        return null;
    }

    public static string? ExtractDraftPdfBase64(string result)
    {
        try
        {
            var found = FindPdfBase64(JsonNode.Parse(result));
            if (found != null) return found;
        }
        catch (JsonException) { }

        var parts = result.Split(',');
        if (parts.Length >= 3)
        {
            var pdfPart = parts[2].Split(':');
            if (pdfPart.Length >= 2)
            {
                var candidate = pdfPart[1].Replace("\"", "").Replace("}", "").Trim();
                if (candidate.StartsWith("JVBER", StringComparison.Ordinal)) return candidate;
            }
        }
        return null;
    }

    private static string DescribeError(string result)
    {
        try
        {
            var json = JsonNode.Parse(result);
            var desc = json?["description"]?.ToString() ?? json?["message"]?.ToString() ?? json?["title"]?.ToString();
            var code = json?["errorCode"]?.ToString() ?? json?["code"]?.ToString();
            if (!string.IsNullOrEmpty(desc)) return string.IsNullOrEmpty(code) ? desc : $"[{code}] {desc}";
        }
        catch (JsonException) { }
        return ViettelClient.Truncate(result, 300);
    }

    private static string? FindProperty(JsonNode? node, string name)
    {
        switch (node)
        {
            case JsonObject obj:
                foreach (var (key, value) in obj)
                {
                    if (key.Equals(name, StringComparison.OrdinalIgnoreCase) && value is JsonValue v)
                    {
                        var s = v.ToString();
                        if (!string.IsNullOrWhiteSpace(s)) return s;
                    }
                }
                foreach (var (_, value) in obj)
                {
                    var found = FindProperty(value, name);
                    if (found != null) return found;
                }
                break;
            case JsonArray arr:
                foreach (var item in arr)
                {
                    var found = FindProperty(item, name);
                    if (found != null) return found;
                }
                break;
        }
        return null;
    }

    private static string? FindPdfBase64(JsonNode? node)
    {
        switch (node)
        {
            case JsonValue v when v.TryGetValue<string>(out var s) && s.StartsWith("JVBER", StringComparison.Ordinal):
                return s;
            case JsonObject obj:
                foreach (var (_, value) in obj)
                {
                    var found = FindPdfBase64(value);
                    if (found != null) return found;
                }
                break;
            case JsonArray arr:
                foreach (var item in arr)
                {
                    var found = FindPdfBase64(item);
                    if (found != null) return found;
                }
                break;
        }
        return null;
    }

    private static JsonArray? FindFirstObjectArray(JsonNode? node)
    {
        switch (node)
        {
            case JsonArray arr:
                if (arr.Count > 0 && arr[0] is JsonObject) return arr;
                foreach (var item in arr)
                {
                    var found = FindFirstObjectArray(item);
                    if (found != null) return found;
                }
                break;
            case JsonObject obj:
                foreach (var (_, value) in obj)
                {
                    var found = FindFirstObjectArray(value);
                    if (found != null) return found;
                }
                break;
        }
        return null;
    }
}
