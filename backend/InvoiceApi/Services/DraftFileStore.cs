using System.Text.RegularExpressions;

namespace InvoiceApi.Services;

/// <summary>Lưu PDF hóa đơn nháp trên server để client tải về (thay cho thư mục c:\temp của bản WinForms).</summary>
public partial class DraftFileStore
{
    private static readonly TimeSpan Retention = TimeSpan.FromDays(30);
    private readonly string _dir;

    public DraftFileStore(IWebHostEnvironment env)
    {
        _dir = Path.Combine(env.ContentRootPath, "App_Data", "drafts");
        Directory.CreateDirectory(_dir);
    }

    public async Task<(string Id, string FileName)> SaveAsync(string invoiceNo, byte[] content)
    {
        CleanupOldFiles();
        var id = Guid.NewGuid().ToString("N");
        var fileName = SanitizeFileName(invoiceNo) + ".pdf";
        await File.WriteAllBytesAsync(Path.Combine(_dir, $"{id}__{fileName}"), content);
        return (id, fileName);
    }

    public (string Path, string FileName)? Find(string id)
    {
        if (!IdPattern().IsMatch(id)) return null;
        var path = Directory.EnumerateFiles(_dir, id + "__*.pdf").FirstOrDefault();
        return path == null ? null : (path, Path.GetFileName(path)[(id.Length + 2)..]);
    }

    public static string SanitizeFileName(string name)
    {
        if (string.IsNullOrWhiteSpace(name)) return "invoice";
        foreach (var c in Path.GetInvalidFileNameChars()) name = name.Replace(c, '_');
        return name.Trim();
    }

    private void CleanupOldFiles()
    {
        foreach (var file in Directory.EnumerateFiles(_dir, "*.pdf"))
        {
            try
            {
                if (DateTime.UtcNow - File.GetCreationTimeUtc(file) > Retention) File.Delete(file);
            }
            catch (IOException) { }
        }
    }

    [GeneratedRegex("^[0-9a-f]{32}$")]
    private static partial Regex IdPattern();
}
