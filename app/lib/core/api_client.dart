import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Gọi backend InvoiceApi. Token được đọc lại ở mỗi request để luôn dùng phiên mới nhất.
class ApiClient {
  ApiClient({
    required String baseUrl,
    required String? Function() tokenReader,
    required void Function() onUnauthorized,
  }) : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 120),
          contentType: Headers.jsonContentType,
        )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = tokenReader();
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        handler.next(options);
      },
      onError: (e, handler) {
        final path = e.requestOptions.path;
        if (e.response?.statusCode == 401 && !path.contains('/auth/')) onUnauthorized();
        handler.next(e);
      },
    ));
  }

  final Dio _dio;

  String get baseUrl => _dio.options.baseUrl;

  Future<dynamic> _run(Future<Response> Function() call) async {
    try {
      final res = await call();
      // Sai địa chỉ máy chủ (vd. trỏ vào Flutter dev server) thì nhận về trang HTML thay vì JSON
      if (res.data is String && (res.data as String).trimLeft().startsWith('<')) {
        throw ApiException('Địa chỉ máy chủ không phải InvoiceApi ($baseUrl). Kiểm tra lại cấu hình máy chủ.');
      }
      return res.data;
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  ApiException _toApiException(DioException e) {
    final status = e.response?.statusCode;
    var data = e.response?.data;
    if (data is List<int>) {
      try {
        data = jsonDecode(utf8.decode(data));
      } catch (_) {}
    }
    if (data is Map && data['message'] != null) return ApiException(data['message'].toString(), statusCode: status);
    if (data is Map && data['title'] != null) return ApiException(data['title'].toString(), statusCode: status);
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.connectionError:
        return ApiException('Không kết nối được máy chủ ($baseUrl). Kiểm tra mạng hoặc địa chỉ máy chủ.');
      case DioExceptionType.receiveTimeout:
        return ApiException('Máy chủ phản hồi quá lâu, vui lòng thử lại.');
      default:
        if (status == 401) return ApiException('Phiên đăng nhập đã hết hạn.', statusCode: 401);
        if (status == 403) return ApiException('Bạn không có quyền thực hiện thao tác này.', statusCode: 403);
        return ApiException('Lỗi ${status ?? ''} ${e.message ?? ''}'.trim(), statusCode: status);
    }
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) => _run(() => _dio.get(path, queryParameters: query));

  Future<dynamic> post(String path, [Object? body]) => _run(() => _dio.post(path, data: body));

  Future<dynamic> put(String path, [Object? body]) => _run(() => _dio.put(path, data: body));

  Future<dynamic> delete(String path) => _run(() => _dio.delete(path));

  Future<Uint8List> getBytes(String path, {Map<String, dynamic>? query}) async {
    final data = await _run(() => _dio.get<List<int>>(path,
        queryParameters: query, options: Options(responseType: ResponseType.bytes)));
    return Uint8List.fromList((data as List<int>?) ?? const []);
  }
}
