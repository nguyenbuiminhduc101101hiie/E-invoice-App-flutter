using System.Text.Json.Nodes;
using InvoiceApi.Infrastructure;
using InvoiceApi.Services;

namespace InvoiceApi.Tests;

public class InvoiceLogicTests
{
    private static Row MakeRow(params (string Key, object? Value)[] values) =>
        new(values.ToDictionary(v => v.Key, v => v.Value));

    private static readonly Dictionary<string, ServiceInfo> Services = new(StringComparer.OrdinalIgnoreCase)
    {
        ["S1"] = new ServiceInfo { Id = "S1", Code = "DAU10", Name = "Dầu nhớt 10%", Unit = "Thùng", Production = 0, TaxPercent = 10 },
        ["S2"] = new ServiceInfo { Id = "S2", Code = "NUOC8", Name = "Nước 8%", Unit = "Chai", Production = 0, TaxPercent = 8 },
        ["S3"] = new ServiceInfo { Id = "S3", Code = "XANG", Name = "Can 20L", Unit = "Can", Production = 20, TaxPercent = 10 },
    };

    [Fact]
    public void NumberUtil_ReadsVietnameseAmount()
    {
        Assert.Equal("Bốn trăm bốn mươi nghìn đồng chẵn", NumberUtil.DocSoThanhChu("440000"));
        Assert.Equal("Một triệu hai trăm ba mươi bốn nghìn năm trăm sáu mươi bảy đồng chẵn", NumberUtil.DocSoThanhChu("1234567"));
        Assert.Equal("Hai mươi mốt nghìn không trăm linh năm đồng chẵn", NumberUtil.DocSoThanhChu("21005"));
    }

    [Fact]
    public void OrderArrays_ParsesJsonAndLegacyFormats()
    {
        Assert.Equal(["a", "b"], OrderArrays.ParseStrings("[\"a\",\"b\"]"));
        Assert.Equal(["Dầu, loại 1", "Nước"], OrderArrays.ParseStrings("[\"Dầu, loại 1\",\"Nước\"]"));
        Assert.Equal([1, 2, 3], OrderArrays.ParseInts("[1,2,3]"));
        Assert.Equal([110000.5, 20000], OrderArrays.ParseDoubles("[110000.5,20000]"));
        Assert.Equal("[\"Dầu\",\"Nước\"]", OrderArrays.FormatStrings(["Dầu", "Nước"]));
        Assert.Equal("[20000.5,3]", OrderArrays.FormatDoubles([20000.5, 3]));
    }

    [Fact]
    public void ConvertToLiter_MultipliesQuantityAndDividesPrice()
    {
        var a = new OrderArraysData
        {
            ServiceIds = ["S3", "S1"],
            Quantities = [2, 3],
            PromotionQuantities = [1, 0],
            UnitPrices = [400000, 110000],
        };
        Assert.Equal(1, a.ConvertToLiter(Services));
        Assert.Equal([40, 3], a.Quantities);
        Assert.Equal([20, 0], a.PromotionQuantities);
        Assert.Equal(20000, a.UnitPrices[0], 6);
        Assert.Equal(110000, a.UnitPrices[1]);
    }

    [Fact]
    public void BuildGroups_SplitsByVatAndComputesTotals()
    {
        var order = new OrderForInvoice(
            MakeRow(("id", "1"), ("DiscountPercent", 0m)),
            new OrderArraysData
            {
                ServiceIds = ["S1", "S2"],
                Quantities = [5, 2],
                PromotionQuantities = [1, 0],
                UnitPrices = [110000, 54000], // đã gồm thuế
            });

        var lines = InvoiceBuilder.BuildLines([order], Services);
        var buyer = InvoiceBuilder.BuildBuyer(MakeRow(("TaxCode", "0101"), ("InvoiceName", "Cty A"), ("InvoiceAddress", "HN\r\n"), ("phone", "09")), []);
        var groups = InvoiceBuilder.BuildGroups(new InvoiceHeader("3604019464", "1/001", "C25TBN", "TM/CK"), buyer, lines);

        Assert.Equal(2, groups.Count);
        Assert.Equal(8, groups[0].TaxPercent);
        Assert.Equal(100000, groups[0].TotalWithoutTax);
        Assert.Equal(8000, groups[0].TotalTax);

        var g10 = groups[1];
        Assert.Equal(10, g10.TaxPercent);
        Assert.Equal(100000, g10.Lines[0].UnitPrice);
        Assert.Equal(4, g10.Lines[0].Quantity);
        Assert.Equal(400000, g10.TotalWithoutTax);
        Assert.Equal(40000, g10.TotalTax);
        Assert.Equal(440000, g10.TotalWithTax);
        Assert.Equal("Bốn trăm bốn mươi nghìn đồng chẵn", g10.AmountInWords);

        var json = JsonNode.Parse(g10.RequestJson)!;
        Assert.Equal("0101", json["buyerInfo"]!["buyerTaxCode"]!.ToString());
        Assert.Equal("Cty A", json["buyerInfo"]!["buyerLegalName"]!.ToString());
        Assert.Equal("HN", json["buyerInfo"]!["buyerAddressLine"]!.ToString());
        Assert.Equal(1, (int)json["itemInfo"]![0]!["lineNumber"]!);
        Assert.Equal(440000, (double)json["summarizeInfo"]!["totalAmountWithTax"]!);
        Assert.Equal(40000, (double)json["taxBreakdowns"]![0]!["taxAmount"]!);
        Assert.True((bool)json["generalInvoiceInfo"]!["paymentStatus"]!);
    }

    [Fact]
    public void BuildLines_MarksFullyPromotionalItems()
    {
        var order = new OrderForInvoice(MakeRow(("DiscountPercent", null)),
            new OrderArraysData { ServiceIds = ["S1"], Quantities = [2], PromotionQuantities = [2], UnitPrices = [110000] });
        var line = Assert.Single(InvoiceBuilder.BuildLines([order], Services));
        Assert.Equal(0, line.UnitPrice);
        Assert.EndsWith("(Hàng KM)", line.ItemName);
    }

    [Fact]
    public void BuildBuyer_HandlesPersonalAndConsumer()
    {
        var personal = InvoiceBuilder.BuildBuyer(MakeRow(("TaxCode", ""), ("Identification", "0123"), ("CustomerName", "Nguyễn A"), ("InvoiceAddress", "HCM"), ("phone", "09")), []);
        Assert.Equal("personal", personal.Kind);
        Assert.Equal("0123", personal.BuyerIdNo);
        Assert.Equal("1", personal.BuyerIdType);
        Assert.Equal("Nguyễn A", personal.BuyerName);

        var consumer = InvoiceBuilder.BuildBuyer(MakeRow(("TaxCode", null), ("Identification", null), ("InvoiceAddress", "HCM")), []);
        Assert.Equal("consumer", consumer.Kind);
        Assert.Equal(InvoiceBuilder.ConsumerBuyerName, consumer.BuyerName);
        Assert.Equal("", consumer.BuyerAddressLine);
    }

    [Fact]
    public void ExtractsViettelResults()
    {
        Assert.Equal("C25TBN123", InvoiceService.ExtractInvoiceNo(
            "{\"errorCode\":null,\"description\":null,\"result\":{\"supplierTaxCode\":\"x\",\"invoiceNo\":\"C25TBN123\",\"transactionID\":\"t\"}}"));
        Assert.Null(InvoiceService.ExtractInvoiceNo("{\"errorCode\":\"ERR\",\"description\":\"Sai mẫu số\",\"result\":null}"));
        Assert.Equal("JVBERi0xLjQ=", InvoiceService.ExtractDraftPdfBase64(
            "{\"errorCode\":null,\"description\":null,\"fileToBytes\":\"JVBERi0xLjQ=\"}"));
    }
}
