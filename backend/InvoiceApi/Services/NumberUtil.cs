namespace InvoiceApi.Services;

/// <summary>Đọc số tiền thành chữ tiếng Việt (giữ nguyên thuật toán của bản WinForms).</summary>
public static class NumberUtil
{
    public static string DocSoThanhChu(string number)
    {
        string strReturn = "";
        if (string.IsNullOrWhiteSpace(number))
            return "";

        string s = number.Trim().Replace(",", "").Replace(" ", "").Replace("-", "");

        int dotIndex = s.IndexOf('.');
        if (dotIndex >= 0)
            s = s.Substring(0, dotIndex);

        while (s.Length > 0 && s.StartsWith('0'))
            s = s.Substring(1);

        string[] so = ["không", "một", "hai", "ba", "bốn", "năm", "sáu", "bảy", "tám", "chín"];
        string[] hang = ["", "nghìn", "triệu", "tỷ"];

        int i, j, donvi, chuc, tram;

        i = s.Length;
        if (i == 0)
            strReturn = so[0] + " ";
        else
        {
            j = 0;
            while (i > 0)
            {
                donvi = s[i - 1] - '0';
                i--;
                chuc = i > 0 ? s[i - 1] - '0' : -1;
                i--;
                tram = i > 0 ? s[i - 1] - '0' : -1;
                i--;

                if ((donvi > 0) || (chuc > 0) || (tram > 0) || (j == 3))
                    strReturn = hang[j] + " " + strReturn;
                j++;
                if (j > 3) j = 1;

                if ((donvi == 1) && (chuc > 1))
                    strReturn = "mốt " + strReturn;
                else if ((donvi == 5) && (chuc > 0))
                    strReturn = "lăm " + strReturn;
                else if (donvi > 0)
                    strReturn = so[donvi] + " " + strReturn;

                if (chuc < 0) break;
                if ((chuc == 0) && (donvi > 0)) strReturn = "linh " + strReturn;
                if (chuc == 1) strReturn = "mười " + strReturn;
                if (chuc > 1) strReturn = so[chuc] + " mươi " + strReturn;

                if (tram < 0) break;
                if ((tram > 0) || (chuc > 0) || (donvi > 0))
                    strReturn = so[tram] + " trăm " + strReturn;
            }
        }

        string result = System.Text.RegularExpressions.Regex.Replace(strReturn.Trim(), @"\s+", " ");
        if (!string.IsNullOrEmpty(result))
            result = char.ToUpper(result[0]) + result.Substring(1) + " đồng chẵn";
        return result;
    }
}
