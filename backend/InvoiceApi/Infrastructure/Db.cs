using System.Data;
using System.Globalization;
using Dapper;
using Microsoft.Data.SqlClient;

namespace InvoiceApi.Infrastructure;

public class Db(IConfiguration config)
{
    private readonly string _connectionString = config.GetConnectionString("Main")
        ?? throw new InvalidOperationException("Thiếu ConnectionStrings:Main trong cấu hình.");

    public async Task<SqlConnection> OpenAsync()
    {
        var cnn = new SqlConnection(_connectionString);
        await cnn.OpenAsync();
        return cnn;
    }

    /// <summary>Query trả về các dòng dạng dictionary không phân biệt hoa thường (tương đương SELECT * vào DataTable).</summary>
    public async Task<List<Row>> QueryRowsAsync(string sql, object? param = null)
    {
        await using var cnn = await OpenAsync();
        var rows = await cnn.QueryAsync(sql, param);
        return rows.Select(r => new Row((IDictionary<string, object?>)r)).ToList();
    }
}

/// <summary>Một dòng dữ liệu từ SQL, truy cập theo tên cột không phân biệt hoa thường.</summary>
public class Row
{
    private readonly Dictionary<string, object?> _values;

    public Row(IDictionary<string, object?> source)
    {
        _values = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
        foreach (var kv in source)
        {
            _values.TryAdd(kv.Key, kv.Value is DBNull ? null : kv.Value);
        }
    }

    public bool Has(string column) => _values.ContainsKey(column);

    public object? Raw(string column) => _values.TryGetValue(column, out var v) ? v : null;

    public string Str(string column) => Raw(column) switch
    {
        null => "",
        IFormattable f => f.ToString(null, CultureInfo.InvariantCulture).Trim(),
        var v => v.ToString()?.Trim() ?? ""
    };

    public string? NullableStr(string column)
    {
        var s = Str(column);
        return s.Length == 0 ? null : s;
    }

    public double Dbl(string column)
    {
        var v = Raw(column);
        if (v == null) return 0;
        try { return Convert.ToDouble(v, CultureInfo.InvariantCulture); }
        catch { return double.TryParse(v.ToString(), NumberStyles.Any, CultureInfo.InvariantCulture, out var d) ? d : 0; }
    }

    public bool Bool(string column)
    {
        var v = Raw(column);
        return v switch
        {
            null => false,
            bool b => b,
            string s => s == "1" || s.Equals("true", StringComparison.OrdinalIgnoreCase),
            _ => Convert.ToDouble(v, CultureInfo.InvariantCulture) != 0
        };
    }

    public bool? NullableBool(string column) => Raw(column) == null ? null : Bool(column);

    public DateTime? Date(string column) => Raw(column) switch
    {
        DateTime d => d,
        DateTimeOffset o => o.DateTime,
        string s when DateTime.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.None, out var d) => d,
        _ => null
    };
}

public class AppException(string message, int statusCode = 400) : Exception(message)
{
    public int StatusCode { get; } = statusCode;
}
