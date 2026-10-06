using Dapper;
using InvoiceApi.Infrastructure;
using InvoiceApi.Models;

namespace InvoiceApi.Services;

public class ServiceInfo
{
    public string Id { get; init; } = "";
    public string Code { get; init; } = "";
    public string Name { get; init; } = "";
    public string InvoiceName { get; init; } = "";
    public string Unit { get; init; } = "";

    /// <summary>Tên in trên hóa đơn: ưu tiên InvoiceName, rỗng thì lấy Name.</summary>
    public string DisplayName => string.IsNullOrWhiteSpace(InvoiceName) ? Name : InvoiceName;
    public double Production { get; init; }
    public double TaxPercent { get; init; }
}

/// <summary>Các mảng item của một đơn trong Orders_Viettel.</summary>
public class OrderArraysData
{
    public List<string> ServiceIds { get; set; } = [];
    public List<string> ServiceNames { get; set; } = [];
    public List<int> Quantities { get; set; } = [];
    public List<int> PromotionQuantities { get; set; } = [];
    public List<double> UnitPrices { get; set; } = [];

    public static OrderArraysData FromRow(Row row) => new()
    {
        ServiceIds = OrderArrays.ParseStrings(row.Str("ServiceIds")),
        ServiceNames = OrderArrays.ParseStrings(row.Str("ServiceNames")),
        Quantities = OrderArrays.ParseInts(row.Str("ServiceQuantities")),
        PromotionQuantities = OrderArrays.ParseInts(row.Str("promotionquantities")),
        UnitPrices = OrderArrays.ParseDoubles(row.Str("UnitPrice")),
    };

    public List<OrderItemDto> ToItems()
    {
        var max = new[] { ServiceIds.Count, ServiceNames.Count, Quantities.Count, PromotionQuantities.Count, UnitPrices.Count }.Max();
        return Enumerable.Range(0, max).Select(i => new OrderItemDto
        {
            ServiceId = i < ServiceIds.Count ? ServiceIds[i] : "",
            ServiceName = i < ServiceNames.Count ? ServiceNames[i] : "",
            Quantity = i < Quantities.Count ? Quantities[i] : 0,
            PromotionQuantity = i < PromotionQuantities.Count ? PromotionQuantities[i] : 0,
            UnitPrice = i < UnitPrices.Count ? UnitPrices[i] : 0,
        }).ToList();
    }

    /// <summary>
    /// Quy đổi sang Lít: số lượng × Production, đơn giá ÷ Production (giữ nguyên đơn giá đã gồm thuế).
    /// Chỉ áp dụng cho service có Production &gt; 0. Trả về số item đã quy đổi.
    /// </summary>
    public int ConvertToLiter(IReadOnlyDictionary<string, ServiceInfo> services)
    {
        var converted = 0;
        for (var i = 0; i < ServiceIds.Count; i++)
        {
            if (string.IsNullOrEmpty(ServiceIds[i]) || !services.TryGetValue(ServiceIds[i], out var svc)) continue;
            if (svc.Production <= 0 || i >= Quantities.Count || i >= UnitPrices.Count) continue;

            Quantities[i] = (int)(svc.Production * Quantities[i]);
            if (i < PromotionQuantities.Count)
            {
                PromotionQuantities[i] = (int)(svc.Production * PromotionQuantities[i]);
            }
            UnitPrices[i] = UnitPrices[i] / svc.Production;
            converted++;
        }
        return converted;
    }
}

public class OrderService(Db db)
{
    private const string SearchSelect = """
        SELECT o.*,
               c.Name AS C_Name, c.TaxCode AS C_TaxCode, c.Identification AS C_Identification,
               c.CustomerName AS C_CustomerName, c.InvoiceName AS C_InvoiceName, c.InvoiceAddress AS C_InvoiceAddress
        FROM Orders_viettel o
        LEFT JOIN Customers c ON o.CustomerName = c.Name
        """;

    public async Task<List<OrderListItemDto>> SearchAsync(OrderSearchQuery q)
    {
        var p = new DynamicParameters();
        p.Add("phone", $"%{q.CustomerPhone?.Trim()}%");
        p.Add("cus", $"%{q.CustomerName?.Trim()}%");
        p.Add("emp", $"%{q.EmployeeName?.Trim()}%");
        p.Add("from", q.From.ToString("yyyy-MM-dd"));
        p.Add("to", q.To.ToString("yyyy-MM-dd"));

        string where;
        if (q.ByPaymentDate)
        {
            // Lọc theo phần ngày (yyyy-MM-dd) của paymentDate đầu tiên trong PaymentHistory (JSON)
            const string pattern = "\"paymentDate\":\"";
            p.Add("pattern", pattern);
            const string datePart = "SUBSTRING(o.PaymentHistory, CHARINDEX(@pattern, o.PaymentHistory) + LEN(@pattern), 10)";
            where = $"""
                WHERE o.PaymentHistory IS NOT NULL AND o.PaymentHistory != '' AND o.PaymentHistory != '[]'
                  AND CHARINDEX(@pattern, o.PaymentHistory) > 0
                  AND {datePart} >= @from AND {datePart} <= @to
                """;
        }
        else
        {
            where = "WHERE CAST(o.createdat AS date) BETWEEN @from AND @to";
        }

        var sql = $"""
            {SearchSelect}
            {where}
              AND o.CustomerPhone LIKE @phone
              AND o.CustomerName LIKE @cus
              AND o.EmployeeNames LIKE @emp
            ORDER BY o.CreatedAt DESC
            """;

        var rows = await db.QueryRowsAsync(sql, p);
        return rows.Select(MapListItem).ToList();
    }

    private static OrderListItemDto MapListItem(Row r)
    {
        var identification = r.NullableStr("C_Identification");
        return new OrderListItemDto
        {
            Id = r.Str("id"),
            CustomerName = r.Str("CustomerName"),
            ShopName = r.NullableStr("C_Name"),
            CustomerPhone = r.NullableStr("CustomerPhone"),
            CustomerAddress = r.NullableStr("CustomerAddress"),
            EmployeeNames = r.NullableStr("EmployeeNames"),
            Items = OrderArraysData.FromRow(r).ToItems(),
            TotalPrice = r.Dbl("TotalPrice"),
            CashAmount = r.Dbl("Cashamount"),
            TransferAmount = r.Dbl("Transferamount"),
            CreatedAt = r.Date("CreatedAt"),
            PaymentStatus = r.NullableStr("PaymentStatus"),
            DeliveryStatus = r.NullableStr("DeliveryStatus"),
            IsDraft = r.Bool("IsDraft"),
            InvoiceNoViettel = r.NullableStr("InvoiceNoViettel"),
            DateInvViettel = r.NullableStr("DateInvViettel"),
            Exported = r.Bool("daxuatthanhcong"),
            HoaDonNoiBo = r.NullableStr("HoaDonNoiBo"),
            TemplateCode = r.NullableStr("mauso"),
            IsConvertToLiter = r.Bool("IsConvertToLiter"),
            TaxCode = r.NullableStr("C_TaxCode"),
            Identification = identification,
            PersonalName = identification != null ? r.NullableStr("C_CustomerName") : null,
            InvoiceName = r.NullableStr("C_InvoiceName"),
            InvoiceAddress = r.NullableStr("C_InvoiceAddress"),
            PaymentHistory = r.NullableStr("PaymentHistory"),
        };
    }

    public async Task<List<Row>> LoadOrdersAsync(IEnumerable<string> ids)
    {
        var list = ids.Distinct().ToList();
        if (list.Count == 0) return [];
        return await db.QueryRowsAsync("SELECT * FROM Orders_viettel WHERE id IN @ids", new { ids = list });
    }

    public async Task<Dictionary<string, ServiceInfo>> LoadServicesAsync(IEnumerable<string> ids)
    {
        var list = ids.Where(x => !string.IsNullOrEmpty(x)).Distinct().ToList();
        var result = new Dictionary<string, ServiceInfo>(StringComparer.OrdinalIgnoreCase);
        if (list.Count == 0) return result;

        var rows = await db.QueryRowsAsync("SELECT * FROM Services WHERE id IN @ids", new { ids = list });
        foreach (var r in rows)
        {
            var svc = new ServiceInfo
            {
                Id = r.Str("id"),
                Code = r.Str("Code"),
                Name = r.Str("Name"),
                InvoiceName = r.Str("InvoiceName"),
                Unit = r.Str("Unit"),
                Production = r.Dbl("Production"),
                TaxPercent = r.Dbl("TaxPercent"),
            };
            result.TryAdd(svc.Id, svc);
        }
        return result;
    }

    public async Task<List<ServiceItem>> ListServicesAsync()
    {
        var rows = await db.QueryRowsAsync("SELECT * FROM Services ORDER BY Name");
        return rows.Select(r => new ServiceItem(r.Str("id"), r.Str("Name"), r.NullableStr("Code"), r.NullableStr("Unit"),
            r.Dbl("Production"), r.Dbl("TaxPercent"))).ToList();
    }

    public async Task<OrderDetailDto> GetDetailAsync(string id)
    {
        var rows = await LoadOrdersAsync([id]);
        var r = rows.FirstOrDefault() ?? throw new AppException("Không tìm thấy đơn hàng.", 404);

        var arrays = OrderArraysData.FromRow(r);
        var isConverted = r.Bool("IsConvertToLiter");
        var autoConverted = 0;

        // Giống form Edit cũ: mở đơn chưa quy đổi thì tự quy đổi sang Lít (lưu khi bấm Lưu)
        var items = arrays.ToItems();
        if (!isConverted)
        {
            var padded = new OrderArraysData
            {
                ServiceIds = items.Select(i => i.ServiceId).ToList(),
                ServiceNames = items.Select(i => i.ServiceName).ToList(),
                Quantities = items.Select(i => i.Quantity).ToList(),
                PromotionQuantities = items.Select(i => i.PromotionQuantity).ToList(),
                UnitPrices = items.Select(i => i.UnitPrice).ToList(),
            };
            autoConverted = padded.ConvertToLiter(await LoadServicesAsync(padded.ServiceIds));
            if (autoConverted > 0) items = padded.ToItems();
        }

        return new OrderDetailDto
        {
            Id = r.Str("id"),
            CustomerName = r.Str("CustomerName"),
            CustomerPhone = r.Str("CustomerPhone"),
            CustomerAddress = r.Str("CustomerAddress"),
            TaxPercent = r.Dbl("TaxPercent"),
            IsConvertToLiter = isConverted || autoConverted > 0,
            AutoConvertedCount = autoConverted,
            Items = items,
        };
    }

    public async Task SaveAsync(string id, SaveOrderRequest req)
    {
        if (req.Items.Count == 0) throw new AppException("Vui lòng thêm ít nhất một item!");
        foreach (var item in req.Items)
        {
            if (string.IsNullOrWhiteSpace(item.ServiceId)) throw new AppException("Có item chưa chọn dịch vụ.");
            if (item.Quantity <= 0) throw new AppException($"Số lượng của '{item.ServiceName}' không hợp lệ.");
            if (item.UnitPrice < 0) throw new AppException($"Đơn giá của '{item.ServiceName}' không hợp lệ.");
            if (item.PromotionQuantity < 0 || item.PromotionQuantity > item.Quantity)
                throw new AppException($"Số lượng khuyến mãi của '{item.ServiceName}' không hợp lệ.");
        }

        // Tổng tiền tính theo số lượng thực (đã trừ khuyến mãi), cộng thuế như form Edit cũ
        var totalWithoutTax = req.Items.Sum(i => i.ActualQuantity * i.UnitPrice);
        var totalPrice = totalWithoutTax * (1 + req.TaxPercent / 100);

        var sql = """
            UPDATE Orders_Viettel SET
                CustomerName = @CustomerName,
                CustomerPhone = @CustomerPhone,
                CustomerAddress = @CustomerAddress,
                ServiceIds = @ServiceIds,
                ServiceNames = @ServiceNames,
                ServiceQuantities = @Quantities,
                promotionquantities = @PromotionQuantities,
                UnitPrice = @UnitPrices,
                TaxPercent = @TaxPercent,
                TotalPrice = @TotalPrice
            """ + (req.IsConvertToLiter ? ", IsConvertToLiter = 1" : "") + " WHERE id = @id";

        await using var cnn = await db.OpenAsync();
        var affected = await cnn.ExecuteAsync(sql, new
        {
            id,
            CustomerName = req.CustomerName.Trim(),
            CustomerPhone = req.CustomerPhone.Trim(),
            CustomerAddress = req.CustomerAddress.Trim(),
            ServiceIds = OrderArrays.FormatStrings(req.Items.Select(i => i.ServiceId)),
            ServiceNames = OrderArrays.FormatStrings(req.Items.Select(i => i.ServiceName)),
            Quantities = OrderArrays.FormatInts(req.Items.Select(i => i.Quantity)),
            PromotionQuantities = OrderArrays.FormatInts(req.Items.Select(i => i.PromotionQuantity)),
            UnitPrices = OrderArrays.FormatDoubles(req.Items.Select(i => i.UnitPrice)),
            TaxPercent = (int)Math.Round(req.TaxPercent),
            TotalPrice = totalPrice,
        });
        if (affected == 0) throw new AppException("Không tìm thấy đơn hàng để lưu.", 404);
    }

    /// <summary>Quy đổi sang Lít và lưu DB các đơn chưa quy đổi (bước tự động trước khi lập hóa đơn).</summary>
    public async Task<int> ConvertPendingOrdersAsync(IEnumerable<Row> orders)
    {
        var pending = orders.Where(o => !o.Bool("IsConvertToLiter")).ToList();
        if (pending.Count == 0) return 0;

        var arrays = pending.ToDictionary(o => o.Str("id"), OrderArraysData.FromRow);
        var services = await LoadServicesAsync(arrays.Values.SelectMany(a => a.ServiceIds));

        var count = 0;
        await using var cnn = await db.OpenAsync();
        foreach (var (orderId, a) in arrays)
        {
            if (a.ConvertToLiter(services) == 0) continue;
            await cnn.ExecuteAsync("""
                UPDATE Orders_Viettel SET
                    ServiceIds = @ServiceIds, ServiceNames = @ServiceNames, ServiceQuantities = @Quantities,
                    promotionquantities = @PromotionQuantities, UnitPrice = @UnitPrices, IsConvertToLiter = 1
                WHERE id = @orderId
                """, new
            {
                orderId,
                ServiceIds = OrderArrays.FormatStrings(a.ServiceIds),
                ServiceNames = OrderArrays.FormatStrings(a.ServiceNames),
                Quantities = OrderArrays.FormatInts(a.Quantities),
                PromotionQuantities = OrderArrays.FormatInts(a.PromotionQuantities),
                UnitPrices = OrderArrays.FormatDoubles(a.UnitPrices),
            });
            count++;
        }
        return count;
    }
}
