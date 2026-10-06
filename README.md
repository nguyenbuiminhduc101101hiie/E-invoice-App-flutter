# Hóa đơn điện tử — Flutter + ASP.NET Core

Phiên bản đa nền tảng (iOS, Android, Web) của **InvoiceClient** (WinForms). Dùng chung database `NPPBaoNgoc@` và API Viettel vInvoice.

```
app/        Ứng dụng Flutter (iOS / Android / Web)
backend/    InvoiceApi — ASP.NET Core 8 Web API (+ unit test)
database/   Script SQL (bảng AppUsers)
```

```
Flutter app ──HTTPS + JWT──▶ InvoiceApi ──▶ SQL Server (Orders_viettel, Customers, Services…)
                                        ├──▶ Viettel vInvoice API
                                        └──▶ SMTP (gửi hóa đơn qua email)
```

App không giữ mật khẩu DB hay tài khoản Viettel — mọi thông tin nhạy cảm nằm ở backend.

## Chức năng (tương ứng bản WinForms)

| WinForms | App mới |
|---|---|
| Search theo ngày tạo / Payment Date, lọc Khách hàng, Nhân viên | Màn **Đơn hàng**: chọn khoảng ngày nhanh, gợi ý tên, lọc trạng thái, tìm nhanh |
| Tô màu dòng chưa quy đổi Lít | Dòng tô cam + thẻ thống kê "Chưa quy đổi Lít" |
| Lập hóa đơn (tách theo VAT, tự quy đổi Lít, kiểm tra HĐ nội bộ…) | **Lập hóa đơn** — có màn xem trước từng hóa đơn VAT, JSON gửi Viettel |
| Lập nháp hóa đơn + nhập số HĐ nội bộ + lưu PDF `c:\temp` | **Lập nháp** — gợi ý số `yyMMdd_STT_TênKhách`, xem / tải PDF ngay trong app |
| Tải file PDF hóa đơn | Nút **PDF**: xem, in, tải về, chia sẻ |
| Edit (frmEditOrder), sửa nhiều đơn (frmEditMultipleOrders) | **Sửa đơn** — chọn nhiều đơn → mỗi đơn một tab, *Lưu tất cả* |
| GetInvoiceList | Màn **HĐ Viettel** |
| Hủy hóa đơn / Cập nhật TT thanh toán (đang ẩn) | Có trong chi tiết HĐ Viettel — chỉ tài khoản **Admin** |
| Gửi email hóa đơn (đang comment) | Nút **Email** trên đơn đã có số HĐ |
| — | Đăng nhập, phân quyền Admin / Nhân viên, quản lý tài khoản, giao diện sáng/tối |

## 1. Chạy backend

Yêu cầu: .NET 8 SDK.

1. Tạo `backend/InvoiceApi/appsettings.Development.json` (file này **không commit**) — xem mẫu các khóa trong `appsettings.json`:
   - `ConnectionStrings:Main` — chuỗi kết nối SQL Server
   - `Jwt:SigningKey` — chuỗi ngẫu nhiên ≥ 32 ký tự
   - `Viettel:Username / Password`, `InvoiceDefaults:TaxCode / TemplateCode / InvoiceSeries`
   - `Smtp:*` nếu dùng gửi email
2. Chạy:
   ```bash
   cd backend/InvoiceApi
   dotnet run
   ```
   Swagger: `http://localhost:5176/swagger`
3. Lần chạy đầu backend tự tạo bảng `dbo.AppUsers` (hoặc chạy tay `database/001_create_app_users.sql`).
   Mở app → màn đăng nhập sẽ hiện **"Tạo tài khoản quản trị"** để tạo Admin đầu tiên.

Unit test logic tính tiền / tách VAT / đọc số: `cd backend && dotnet test`

## 2. Chạy app Flutter

Yêu cầu: Flutter 3.35+.

```bash
cd app
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:5176     # Web
flutter run -d <android|ios device> --dart-define=API_BASE_URL=https://hoadon.congty.vn
```

Không truyền `API_BASE_URL` thì bản web gọi về chính domain đang mở; bản mobile cho nhập địa chỉ máy chủ ở màn đăng nhập.

## 3. Triển khai

**Web + API trên cùng 1 server (khuyến nghị):**
```bash
cd app && flutter build web --release
cd ../backend/InvoiceApi && dotnet publish -c Release -o ../../publish
# copy app/build/web/* vào publish/wwwroot/
```
Chạy `publish/InvoiceApi.exe` trên IIS / Windows Service, cấu hình `appsettings.Production.json` (hoặc biến môi trường, ví dụ `ConnectionStrings__Main`). **Bắt buộc dùng HTTPS** — Android/iOS chặn HTTP thường, và mật khẩu đăng nhập đi qua kết nối này.

**Mobile:**
```bash
flutter build apk --release --dart-define=API_BASE_URL=https://hoadon.congty.vn       # Android
flutter build ipa --release --dart-define=API_BASE_URL=https://hoadon.congty.vn       # iOS (cần máy Mac)
```

## Ghi chú nghiệp vụ

- Quy tắc tính tiền giữ nguyên bản WinForms: đơn giá trong DB **đã gồm VAT** → tách giá trước thuế theo `Services.TaxPercent`, làm tròn đơn giá, tính thuế theo từng dòng, gom hóa đơn theo mức VAT.
- Khi lập HĐ / nháp, đơn chưa quy đổi Lít được quy đổi (SL × Production, đơn giá ÷ Production) và lưu DB trước.
- Nếu Viettel lập được một phần (ví dụ HĐ VAT 8% thành công, VAT 10% lỗi), backend vẫn ghi `daxuatthanhcong = 1` và các số HĐ đã có để tránh xuất trùng, đồng thời báo lỗi phần còn lại.
- Lập hóa đơn được khóa tuần tự trên server để 2 người không lập trùng cùng lúc.
