# E-Invoice App — Hóa đơn điện tử đa nền tảng

Ứng dụng quản lý đơn hàng và **lập hóa đơn điện tử qua Viettel vInvoice**, chạy trên **Android, iOS và Web** từ một mã nguồn Flutter, với backend **ASP.NET Core 8**.

Đây là phiên bản viết lại của ứng dụng desktop WinForms *InvoiceClient*: giữ nguyên nghiệp vụ tính tiền và xuất hóa đơn, nhưng dùng được trên điện thoại, trình duyệt, có đăng nhập và phân quyền.

## Mục lục

- [Kiến trúc](#kiến-trúc)
- [Chức năng](#chức-năng)
- [Công nghệ sử dụng](#công-nghệ-sử-dụng)
- [Cấu trúc thư mục](#cấu-trúc-thư-mục)
- [Cài đặt và chạy](#cài-đặt-và-chạy)
- [Triển khai](#triển-khai)
- [Ghi chú nghiệp vụ](#ghi-chú-nghiệp-vụ)

## Kiến trúc

```
┌──────────────────────┐   HTTPS + JWT   ┌──────────────────┐ ──▶ SQL Server (đơn hàng, khách hàng, dịch vụ…)
│ Flutter app          │ ──────────────▶ │ InvoiceApi       │ ──▶ Viettel vInvoice API (lập / tra cứu / hủy HĐ)
│ Android · iOS · Web  │                 │ ASP.NET Core 8   │ ──▶ SMTP (gửi hóa đơn qua email)
└──────────────────────┘                 └──────────────────┘
```

App **không lưu** mật khẩu database hay tài khoản Viettel. Mọi thông tin nhạy cảm chỉ nằm ở backend, app chỉ giữ token JWT của người dùng.

## Chức năng

### Quản lý đơn hàng
- Tìm đơn theo **ngày tạo** hoặc **ngày thanh toán**, có sẵn các khoảng ngày nhanh (hôm nay, tuần này, tháng này…).
- Lọc theo khách hàng, nhân viên (có gợi ý tên) và trạng thái hóa đơn; tìm nhanh trong kết quả.
- Đơn **chưa quy đổi sang Lít** được tô màu và đếm riêng trên thẻ thống kê.
- **Sửa đơn**: sửa một đơn, hoặc chọn nhiều đơn để mỗi đơn mở thành một tab rồi *Lưu tất cả*.

### Lập hóa đơn điện tử (Viettel vInvoice)
- **Lập hóa đơn** từ các đơn đã chọn: tự tách hóa đơn theo mức VAT, tự quy đổi Lít, kiểm tra số hóa đơn nội bộ.
- **Xem trước** từng hóa đơn theo mức VAT và JSON gửi sang Viettel trước khi xuất.
- **Lập nháp**: gợi ý số hóa đơn nội bộ dạng `yyMMdd_STT_TênKhách`, xem và tải PDF nháp ngay trong app.
- **PDF hóa đơn**: xem, in, tải về, chia sẻ.
- **Gửi email** hóa đơn cho khách với đơn đã có số hóa đơn.

### Tra cứu hóa đơn Viettel
- Danh sách hóa đơn đã phát hành trên hệ thống Viettel.
- **Hủy hóa đơn** và **cập nhật trạng thái thanh toán** (chỉ dành cho Admin).

### Tài khoản và hệ thống
- Đăng nhập bằng JWT, phân quyền **Admin / Nhân viên**.
- Lần chạy đầu: màn hình tạo tài khoản quản trị đầu tiên.
- Admin quản lý tài khoản (thêm, sửa, xóa); người dùng tự đổi mật khẩu.
- Giao diện sáng / tối, hiển thị tiếng Việt.

## Công nghệ sử dụng

### Frontend: `app/`
| Công nghệ | Vai trò |
|---|---|
| [Flutter](https://flutter.dev) 3.35+ / Dart 3.9 | UI đa nền tảng: Android, iOS, Web |
| [flutter_riverpod](https://pub.dev/packages/flutter_riverpod) | Quản lý state |
| [go_router](https://pub.dev/packages/go_router) | Điều hướng, chặn route khi chưa đăng nhập |
| [dio](https://pub.dev/packages/dio) | HTTP client, đính kèm JWT |
| [printing](https://pub.dev/packages/printing) | Xem, in, chia sẻ PDF |
| [shared_preferences](https://pub.dev/packages/shared_preferences) | Lưu token, địa chỉ server, theme |
| [intl](https://pub.dev/packages/intl), flutter_localizations | Định dạng tiền, ngày theo kiểu Việt Nam |
| [google_fonts](https://pub.dev/packages/google_fonts) | Font chữ |

### Backend: `backend/`
| Công nghệ | Vai trò |
|---|---|
| ASP.NET Core 8 Web API | REST API (`/api/auth`, `/api/orders`, `/api/invoices`, `/api/lookups`, `/api/users`) |
| [Dapper](https://github.com/DapperLib/Dapper) + Microsoft.Data.SqlClient | Truy vấn SQL Server |
| JWT Bearer Authentication | Xác thực, phân quyền theo vai trò |
| [BCrypt.Net-Next](https://github.com/BcryptNet/bcrypt.net) | Băm mật khẩu |
| Swashbuckle (Swagger) | Tài liệu API |
| Viettel vInvoice REST API | Phát hành, tra cứu, hủy hóa đơn điện tử |
| SMTP (System.Net.Mail) | Gửi hóa đơn qua email |
| xUnit | Unit test cho logic tính tiền, tách VAT, đọc số thành chữ |

### Cơ sở dữ liệu
- **Microsoft SQL Server**: dùng chung database với bản WinForms. Bảng `AppUsers` do app thêm vào (script trong `database/`).

## Cấu trúc thư mục

```
app/                       Ứng dụng Flutter
  lib/core/                API client, theme, formatter, widget dùng chung, PDF viewer
  lib/features/            Các màn hình: auth, orders, invoices, viettel, users, settings, shell
  lib/models/              Model dữ liệu
  lib/state/               Provider Riverpod (phiên đăng nhập, danh mục)
backend/
  InvoiceApi/              ASP.NET Core Web API
    Controllers/           Endpoint REST
    Services/              Nghiệp vụ: đơn hàng, lập HĐ, Viettel client, email, user
    Infrastructure/        Kết nối DB, cấu hình
  InvoiceApi.Tests/        Unit test (xUnit)
database/                  Script SQL
```

## Cài đặt và chạy

### 1. Backend

Yêu cầu: **.NET 8 SDK**, SQL Server.

1. Tạo file `backend/InvoiceApi/appsettings.Development.json` (file này đã nằm trong `.gitignore`, **không commit**). Các khóa cần điền, xem mẫu trong `appsettings.json`:
   - `ConnectionStrings:Main`: chuỗi kết nối SQL Server
   - `Jwt:SigningKey`: chuỗi ngẫu nhiên, tối thiểu 32 ký tự
   - `Viettel:Username / Password`, `InvoiceDefaults:TaxCode / TemplateCode / InvoiceSeries`
   - `Smtp:*`: nếu dùng chức năng gửi email
2. Chạy:
   ```bash
   cd backend/InvoiceApi
   dotnet run
   ```
   Swagger: `http://localhost:5176/swagger`
3. Lần chạy đầu, backend tự tạo bảng `dbo.AppUsers` (hoặc chạy tay `database/001_create_app_users.sql`). Mở app, màn đăng nhập sẽ hiện **"Tạo tài khoản quản trị"** để tạo Admin đầu tiên.

Chạy unit test:
```bash
cd backend && dotnet test
```

### 2. App Flutter

Yêu cầu: **Flutter 3.35+**.

```bash
cd app
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:5176          # Web
flutter run -d <thiết bị> --dart-define=API_BASE_URL=https://hoadon.congty.vn   # Android / iOS
```

Nếu không truyền `API_BASE_URL`: bản web gọi về chính domain đang mở, bản mobile cho nhập địa chỉ server ở màn đăng nhập.

## Triển khai

**Web và API trên cùng một server (khuyến nghị):**
```bash
cd app && flutter build web --release
cd ../backend/InvoiceApi && dotnet publish -c Release -o ../../publish
# copy app/build/web/* vào publish/wwwroot/
```
Chạy `publish/InvoiceApi.exe` trên IIS hoặc dưới dạng Windows Service. Cấu hình bằng `appsettings.Production.json` hoặc biến môi trường (ví dụ `ConnectionStrings__Main`). **Bắt buộc dùng HTTPS**: Android/iOS chặn HTTP thường, và mật khẩu đăng nhập đi qua kết nối này.

**Mobile:**
```bash
flutter build apk --release --dart-define=API_BASE_URL=https://hoadon.congty.vn   # Android
flutter build ipa --release --dart-define=API_BASE_URL=https://hoadon.congty.vn   # iOS (cần máy Mac)
```

## Ghi chú nghiệp vụ

- Đơn giá trong DB **đã gồm VAT**. Backend tách giá trước thuế theo `Services.TaxPercent`, làm tròn đơn giá, tính thuế theo từng dòng, rồi gom hóa đơn theo mức VAT (giữ nguyên quy tắc của bản WinForms).
- Khi lập hóa đơn hoặc nháp, đơn chưa quy đổi Lít được quy đổi (SL × Production, đơn giá ÷ Production) và lưu vào DB trước.
- Nếu Viettel chỉ lập được một phần (ví dụ HĐ VAT 8% thành công, VAT 10% lỗi), backend vẫn ghi nhận các số hóa đơn đã có để tránh xuất trùng, đồng thời báo lỗi phần còn lại.
- Việc lập hóa đơn được khóa tuần tự trên server để hai người không lập trùng cùng lúc.
