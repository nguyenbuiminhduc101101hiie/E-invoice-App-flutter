using System.Globalization;
using System.Text.Encodings.Web;
using System.Text.Json;

namespace InvoiceApi.Services;

/// <summary>
/// Các cột ServiceIds, ServiceNames, ServiceQuantities, promotionquantities, UnitPrice
/// trong Orders_Viettel lưu dạng chuỗi mảng, ví dụ ["id1","id2"] hoặc [1,2].
/// </summary>
public static class OrderArrays
{
    private static readonly JsonSerializerOptions RelaxedJson = new()
    {
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };

    public static List<string> ParseStrings(string? raw)
    {
        raw = raw?.Trim() ?? "";
        if (raw.Length == 0) return [];
        if (raw.StartsWith('['))
        {
            try
            {
                using var doc = JsonDocument.Parse(raw);
                return doc.RootElement.EnumerateArray()
                    .Select(e => (e.ValueKind == JsonValueKind.String ? e.GetString() : e.ToString())?.Trim() ?? "")
                    .ToList();
            }
            catch (JsonException) { }
        }
        // Cách tách giống bản WinForms: bỏ [ ] " rồi tách theo dấu phẩy
        return raw.Replace("[", "").Replace("]", "").Replace("\"", "")
            .Split(',', StringSplitOptions.RemoveEmptyEntries)
            .Select(x => x.Trim())
            .ToList();
    }

    public static List<int> ParseInts(string? raw) =>
        ParseStrings(raw).Select(x => int.TryParse(x, NumberStyles.Integer, CultureInfo.InvariantCulture, out var v) ? v : 0).ToList();

    public static List<double> ParseDoubles(string? raw) =>
        ParseStrings(raw).Select(x => double.TryParse(x, NumberStyles.Any, CultureInfo.InvariantCulture, out var v) ? v : 0.0).ToList();

    public static string FormatStrings(IEnumerable<string> values) =>
        JsonSerializer.Serialize(values, RelaxedJson);

    public static string FormatInts(IEnumerable<int> values) =>
        "[" + string.Join(",", values.Select(v => v.ToString(CultureInfo.InvariantCulture))) + "]";

    public static string FormatDoubles(IEnumerable<double> values) =>
        "[" + string.Join(",", values.Select(v => v.ToString(CultureInfo.InvariantCulture))) + "]";
}
