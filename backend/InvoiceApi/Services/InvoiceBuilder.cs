using System.Globalization;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;
using InvoiceApi.Infrastructure;
using InvoiceApi.Models;

namespace InvoiceApi.Services;

public record InvoiceHeader(string TaxCode, string TemplateCode, string InvoiceSeries, string PaymentMethod);

/// <summary>Đơn hàng đã sẵn sàng để lập hóa đơn (mảng item đã quy đổi Lít nếu cần).</summary>
public record OrderForInvoice(Row Row, OrderArraysData Arrays);

public class BuyerData
{
    public string Kind { get; set; } = "unknown";
    public string BuyerName { get; set; } = "";
    public string BuyerLegalName { get; set; } = "";
    public string BuyerTaxCode { get; set; } = "";
    public string BuyerAddressLine { get; set; } = "";
    public string BuyerPhoneNumber { get; set; } = "";
    public string BuyerIdNo { get; set; } = "";
    public string BuyerIdType { get; set; } = "";
}

/// <summary>
/// Dựng JSON createInvoice / createInvoiceDraftPreview cho Viettel, tách hóa đơn theo mức VAT.
/// Giữ nguyên quy tắc tính tiền của createInvoiceExamples + BuildInvoiceJson ở bản WinForms.
/// </summary>
public static class InvoiceBuilder
{
    public const string ConsumerBuyerName = "BÁN CHO NGƯỜI TIÊU DÙNG";

    private static readonly JsonSerializerOptions JsonOut = new()
    {
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };

    public static BuyerData BuildBuyer(Row? customer, List<string> warnings)
    {
        var buyer = new BuyerData();
        if (customer == null)
        {
            warnings.Add("Không tìm thấy khách hàng theo SĐT của đơn trong bảng Customers — thông tin người mua sẽ để trống.");
            return buyer;
        }

        var taxCode = customer.Str("TaxCode");
        var identification = customer.Str("Identification");

        if (!string.IsNullOrEmpty(taxCode))
        {
            buyer.Kind = "company";
            buyer.BuyerTaxCode = taxCode;
            buyer.BuyerLegalName = customer.Str("InvoiceName");
        }
        else if (!string.IsNullOrEmpty(identification))
        {
            buyer.Kind = "personal";
            buyer.BuyerName = customer.Str("CustomerName");
            buyer.BuyerIdNo = identification;
            buyer.BuyerIdType = "1";
        }
        else
        {
            buyer.Kind = "consumer";
            buyer.BuyerName = ConsumerBuyerName;
            return buyer;
        }

        buyer.BuyerAddressLine = customer.Str("InvoiceAddress").Replace("\n", "").Replace("\r", "");
        buyer.BuyerPhoneNumber = customer.Str("phone");
        return buyer;
    }

    public static List<InvoiceLinePreview> BuildLines(IEnumerable<OrderForInvoice> orders, IReadOnlyDictionary<string, ServiceInfo> services)
    {
        var lines = new List<InvoiceLinePreview>();
        foreach (var order in orders)
        {
            var a = order.Arrays;
            // Số phần tử các mảng không khớp thì bỏ qua đơn (giống bản cũ)
            if (a.ServiceIds.Count != a.Quantities.Count || a.Quantities.Count != a.UnitPrices.Count)
                continue;

            var discount = (double)Convert.ToInt32(order.Row.Dbl("DiscountPercent"));

            for (var j = 0; j < a.ServiceIds.Count; j++)
            {
                if (!services.TryGetValue(a.ServiceIds[j], out var svc)) continue;

                var itemTax = svc.TaxPercent;
                // UnitPrice trong DB đã gồm thuế → tách giá trước thuế
                var unitPriceBeforeTax = itemTax > 0 ? a.UnitPrices[j] / (1 + itemTax / 100) : a.UnitPrices[j];
                var promo = j < a.PromotionQuantities.Count ? a.PromotionQuantities[j] : 0;
                var actualQuantity = a.Quantities[j] - promo;

                var roundedUnitPrice = Math.Round(unitPriceBeforeTax, 0, MidpointRounding.AwayFromZero);
                var amountWithoutTax = roundedUnitPrice * actualQuantity;
                var taxAmount = (amountWithoutTax - amountWithoutTax * (discount / 100)) * (itemTax / 100);

                var line = new InvoiceLinePreview
                {
                    ItemCode = svc.Code,
                    ItemName = svc.DisplayName,
                    UnitName = svc.Production == 0 ? svc.Unit : "Lít",
                    UnitPrice = roundedUnitPrice,
                    Quantity = actualQuantity,
                    AmountWithoutTax = Math.Round(amountWithoutTax, 0, MidpointRounding.AwayFromZero),
                    TaxAmount = Math.Round(taxAmount, 0, MidpointRounding.AwayFromZero),
                    TaxPercent = Convert.ToInt32(itemTax),
                    Discount = discount,
                };
                if (actualQuantity == 0)
                {
                    line.UnitPrice = 0;
                    line.ItemName += " (Hàng KM)";
                }
                lines.Add(line);
            }
        }
        return lines;
    }

    public static List<InvoiceGroupPreview> BuildGroups(InvoiceHeader header, BuyerData buyer, List<InvoiceLinePreview> lines)
    {
        var groups = new List<InvoiceGroupPreview>();
        foreach (var g in lines.GroupBy(l => l.TaxPercent).OrderBy(g => g.Key))
        {
            var groupLines = g.ToList();
            for (var i = 0; i < groupLines.Count; i++) groupLines[i].LineNumber = i + 1;

            double sum = 0, totalWithTax = 0, totalTax = 0, totalDiscount = 0;
            foreach (var l in groupLines)
            {
                sum += l.AmountWithoutTax;
                totalWithTax += l.AmountWithoutTax + l.TaxAmount;
                totalTax += l.TaxAmount;
                totalDiscount += l.AmountWithoutTax * (l.Discount / 100);
            }

            var group = new InvoiceGroupPreview
            {
                TaxPercent = g.Key,
                TotalWithoutTax = sum - totalDiscount,
                TotalTax = totalTax,
                TotalWithTax = totalWithTax - totalDiscount,
                DiscountAmount = totalDiscount,
                Lines = groupLines,
            };
            group.AmountInWords = NumberUtil.DocSoThanhChu(Num(group.TotalWithTax).Replace("-", ""));
            group.RequestJson = BuildJson(header, buyer, group, sum);
            groups.Add(group);
        }
        return groups;
    }

    private static string BuildJson(InvoiceHeader header, BuyerData buyer, InvoiceGroupPreview group, double sumWithoutDiscount)
    {
        var issuedDate = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();

        var items = new JsonArray();
        foreach (var l in group.Lines)
        {
            items.Add(new JsonObject
            {
                ["lineNumber"] = l.LineNumber,
                ["itemCode"] = l.ItemCode,
                ["itemName"] = l.ItemName.Replace("\r", "  ").Trim(),
                ["unitName"] = l.UnitName,
                ["unitPrice"] = l.UnitPrice,
                ["quantity"] = l.Quantity,
                ["itemTotalAmountWithoutTax"] = l.AmountWithoutTax,
                ["taxPercentage"] = l.TaxPercent,
                ["taxAmount"] = l.TaxAmount,
                ["discount"] = l.Discount,
                ["itemDiscount"] = 0,
            });
        }

        var root = new JsonObject
        {
            ["generalInvoiceInfo"] = new JsonObject
            {
                ["invoiceType"] = "1",
                ["templateCode"] = header.TemplateCode.Trim(),
                ["invoiceSeries"] = header.InvoiceSeries.Trim(),
                ["transactionUuid"] = Guid.NewGuid().ToString(),
                ["invoiceIssuedDate"] = issuedDate,
                ["currencyCode"] = "VND",
                ["adjustmentType"] = "1",
                ["paymentStatus"] = true,
                ["paymentTypeName"] = header.PaymentMethod,
                ["cusGetInvoiceRight"] = true,
                ["buyerIdNo"] = buyer.BuyerIdNo,
                ["buyerIdType"] = buyer.BuyerIdType,
            },
            ["buyerInfo"] = new JsonObject
            {
                ["buyerLegalName"] = buyer.BuyerLegalName,
                ["buyerName"] = buyer.BuyerName,
                ["buyerTaxCode"] = buyer.BuyerTaxCode,
                ["buyerAddressLine"] = buyer.BuyerAddressLine,
                ["buyerPhoneNumber"] = buyer.BuyerPhoneNumber,
                ["buyerEmail"] = "",
                ["buyerIdNo"] = buyer.BuyerIdNo,
                ["buyerIdType"] = buyer.BuyerIdType,
            },
            ["payments"] = new JsonArray(new JsonObject { ["paymentMethodName"] = header.PaymentMethod }),
            ["deliveryInfo"] = new JsonObject(),
            ["itemInfo"] = items,
            ["discountItemInfo"] = new JsonArray(),
            ["summarizeInfo"] = new JsonObject
            {
                ["sumOfTotalLineAmountWithoutTax"] = sumWithoutDiscount,
                ["totalAmountWithoutTax"] = group.TotalWithoutTax,
                ["totalTaxAmount"] = group.TotalTax,
                ["totalAmountWithTax"] = group.TotalWithTax,
                ["totalAmountWithTaxInWords"] = group.AmountInWords,
                ["discountAmount"] = group.DiscountAmount,
                ["taxPercentage"] = Convert.ToInt32(group.TaxPercent),
            },
            ["taxBreakdowns"] = new JsonArray(new JsonObject
            {
                ["taxPercentage"] = group.TaxPercent,
                ["taxableAmount"] = Math.Round(group.TotalWithoutTax, 0, MidpointRounding.AwayFromZero),
                ["taxAmount"] = Math.Round(group.TotalTax, 0, MidpointRounding.AwayFromZero),
            }),
        };
        return root.ToJsonString(JsonOut);
    }

    private static string Num(double v) => v.ToString(CultureInfo.InvariantCulture);
}
