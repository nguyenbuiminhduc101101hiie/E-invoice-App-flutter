using System.Net;
using System.Text;
using InvoiceApi.Infrastructure;
using InvoiceApi.Services;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;

// Tiện ích: dotnet run -- hash-password <mật khẩu>  → in chuỗi BCrypt để INSERT tay vào dbo.AppUsers
if (args.Length >= 2 && args[0] == "hash-password")
{
    Console.WriteLine(BCrypt.Net.BCrypt.HashPassword(args[1]));
    return;
}

var builder = WebApplication.CreateBuilder(args);
var config = builder.Configuration;

builder.Services.Configure<ViettelOptions>(config.GetSection("Viettel"));
builder.Services.Configure<InvoiceDefaultsOptions>(config.GetSection("InvoiceDefaults"));
builder.Services.Configure<JwtOptions>(config.GetSection("Jwt"));
builder.Services.Configure<SmtpOptions>(config.GetSection("Smtp"));

var jwt = config.GetSection("Jwt").Get<JwtOptions>() ?? new JwtOptions();
if (Encoding.UTF8.GetByteCount(jwt.SigningKey) < 32)
    throw new InvalidOperationException("Jwt:SigningKey phải dài tối thiểu 32 ký tự.");

builder.Services.AddSingleton<Db>();
builder.Services.AddSingleton<DraftFileStore>();
builder.Services.AddScoped<UserService>();
builder.Services.AddScoped<OrderService>();
builder.Services.AddScoped<InvoiceService>();
builder.Services.AddScoped<EmailService>();
builder.Services.AddScoped<ViettelClient>();

builder.Services.AddHttpClient(ViettelClient.HttpClientName, client =>
    {
        var opt = config.GetSection("Viettel").Get<ViettelOptions>() ?? new ViettelOptions();
        client.Timeout = TimeSpan.FromSeconds(opt.TimeoutSeconds);
    })
    .ConfigurePrimaryHttpMessageHandler(() =>
    {
        var opt = config.GetSection("Viettel").Get<ViettelOptions>() ?? new ViettelOptions();
        var handler = new HttpClientHandler();
        if (opt.UseProxy && !string.IsNullOrWhiteSpace(opt.ProxyHost))
        {
            handler.Proxy = new WebProxy(opt.ProxyHost, opt.ProxyPort);
            handler.UseProxy = true;
        }
        return handler;
    });

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(o =>
    {
        o.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = jwt.Issuer,
            ValidateAudience = true,
            ValidAudience = jwt.Audience,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt.SigningKey)),
            ClockSkew = TimeSpan.FromMinutes(1),
        };
    });
builder.Services.AddAuthorization();

var allowedOrigins = config.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [];
builder.Services.AddCors(o => o.AddDefaultPolicy(p =>
{
    if (allowedOrigins.Length == 0 || allowedOrigins.Contains("*")) p.AllowAnyOrigin();
    else p.WithOrigins(allowedOrigins);
    p.AllowAnyHeader().AllowAnyMethod().WithExposedHeaders("Content-Disposition");
}));

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo { Title = "Invoice API", Version = "v1" });
    var scheme = new OpenApiSecurityScheme
    {
        Name = "Authorization",
        Type = SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
        In = ParameterLocation.Header,
        Reference = new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "Bearer" },
    };
    c.AddSecurityDefinition("Bearer", scheme);
    c.AddSecurityRequirement(new OpenApiSecurityRequirement { [scheme] = [] });
});

var app = builder.Build();

// Lỗi nghiệp vụ trả về {"message": "..."} để app hiển thị trực tiếp
app.UseExceptionHandler(errorApp => errorApp.Run(async ctx =>
{
    var ex = ctx.Features.Get<IExceptionHandlerFeature>()?.Error;
    var (status, message) = ex switch
    {
        AppException appEx => (appEx.StatusCode, appEx.Message),
        TaskCanceledException => (504, "Hết thời gian chờ phản hồi từ Viettel."),
        Microsoft.Data.SqlClient.SqlException => (500, "Lỗi cơ sở dữ liệu: " + ex.Message),
        _ => (500, "Lỗi hệ thống: " + ex?.Message),
    };
    if (status >= 500)
        ctx.RequestServices.GetRequiredService<ILogger<Program>>().LogError(ex, "Unhandled error");
    ctx.Response.StatusCode = status;
    await ctx.Response.WriteAsJsonAsync(new { message });
}));

if (config.GetValue("Swagger:Enabled", app.Environment.IsDevelopment()))
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

// Phục vụ luôn bản Flutter Web (copy build/web vào wwwroot) để chỉ cần deploy 1 server
app.UseDefaultFiles();
app.UseStaticFiles();

app.UseCors();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
// Đường dẫn /api/* không tồn tại trả 404; các đường dẫn khác (không phải file) trả về app Flutter
app.MapFallback("api/{**slug}", () => Results.NotFound(new { message = "Không tìm thấy API." }));
app.MapFallbackToFile("index.html");

if (config.GetValue("Database:EnsureUsersTable", true))
{
    try
    {
        using var scope = app.Services.CreateScope();
        await scope.ServiceProvider.GetRequiredService<UserService>().EnsureTableAsync();
    }
    catch (Exception ex)
    {
        app.Logger.LogError(ex, "Không tạo/kiểm tra được bảng AppUsers. Hãy chạy database/001_create_app_users.sql thủ công.");
    }
}

app.Run();
