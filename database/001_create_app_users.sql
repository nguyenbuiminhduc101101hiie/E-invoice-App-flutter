-- Bảng tài khoản đăng nhập cho app Hóa đơn (Flutter + InvoiceApi).
-- Backend tự chạy script tương đương khi khởi động (Database:EnsureUsersTable = true).
-- Chạy tay script này nếu tài khoản SQL của backend không có quyền CREATE TABLE.
-- Tài khoản Admin đầu tiên được tạo từ màn hình đăng nhập của app khi bảng còn trống.

IF OBJECT_ID(N'dbo.AppUsers', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AppUsers (
        Id           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AppUsers PRIMARY KEY,
        Username     NVARCHAR(50)  NOT NULL,
        PasswordHash NVARCHAR(200) NOT NULL,   -- BCrypt, không lưu mật khẩu gốc
        FullName     NVARCHAR(100) NULL,
        Role         NVARCHAR(20)  NOT NULL CONSTRAINT DF_AppUsers_Role DEFAULT (N'User'),   -- Admin | User
        IsActive     BIT           NOT NULL CONSTRAINT DF_AppUsers_IsActive DEFAULT (1),
        CreatedAt    DATETIME2(0)  NOT NULL CONSTRAINT DF_AppUsers_CreatedAt DEFAULT (SYSDATETIME()),
        LastLoginAt  DATETIME2(0)  NULL,
        CONSTRAINT UQ_AppUsers_Username UNIQUE (Username)
    );
END
GO
