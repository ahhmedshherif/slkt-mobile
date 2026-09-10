import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.fields = const {}});

  final String message;
  final int? statusCode;
  final Map<String, dynamic> fields;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient()
    : dio = Dio(
        BaseOptions(
          baseUrl: const String.fromEnvironment(
            'API_BASE_URL',
            defaultValue: 'https://tktsapp.com/api/v1',
          ),
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 35),
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        ),
      ) {
    dio.interceptors.add(_GetConnectionRetryInterceptor(dio));
  }

  static const storage = FlutterSecureStorage();
  final Dio dio;

  Future<String?> tokenFor(String audience) =>
      storage.read(key: '${audience}_token');

  Future<void> saveToken(String audience, String token) =>
      storage.write(key: '${audience}_token', value: token);

  Future<void> clearToken(String audience) =>
      storage.delete(key: '${audience}_token');

  Future<Map<String, dynamic>> get(
    String path, {
    String? audience,
    Map<String, dynamic>? query,
  }) => _request('GET', path, audience: audience, query: query);

  Future<Map<String, dynamic>> post(
    String path, {
    String? audience,
    Object? data,
  }) => _request('POST', path, audience: audience, data: data);

  Future<Map<String, dynamic>> patch(
    String path, {
    String? audience,
    Object? data,
  }) => _request('PATCH', path, audience: audience, data: data);

  Future<Map<String, dynamic>> delete(
    String path, {
    String? audience,
    Object? data,
  }) => _request('DELETE', path, audience: audience, data: data);

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    String? audience,
    Object? data,
    Map<String, dynamic>? query,
  }) async {
    try {
      final token = audience == null ? null : await tokenFor(audience);
      final response = await dio.request<Object?>(
        path,
        data: data,
        queryParameters: query,
        options: Options(
          method: method,
          headers: token == null ? null : {'Authorization': 'Bearer $token'},
        ),
      );
      final value = response.data;
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      if (value is String && value.isNotEmpty) {
        final decoded = jsonDecode(value);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      }
      return const {};
    } on DioException catch (error) {
      final response = error.response;
      final raw = response?.data;
      var message = 'Something went wrong. Please try again.';
      var fields = <String, dynamic>{};
      if (raw is Map) {
        final map = Map<String, dynamic>.from(raw);
        message = (map['message'] ?? message).toString();
        if (map['errors'] is Map) {
          fields = Map<String, dynamic>.from(map['errors']);
        }
      } else if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout) {
        message =
            'TKTS APP server is temporarily unavailable. Your internet is connected; please retry in a moment.';
      }
      throw ApiException(
        message,
        statusCode: response?.statusCode,
        fields: fields,
      );
    }
  }
}

bool shouldRetryApiRequest(String method, DioExceptionType type, int attempt) =>
    method.toUpperCase() == 'GET' &&
    attempt < 2 &&
    (type == DioExceptionType.connectionError ||
        type == DioExceptionType.connectionTimeout);

class _GetConnectionRetryInterceptor extends Interceptor {
  _GetConnectionRetryInterceptor(this.client);

  final Dio client;

  @override
  Future<void> onError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    final attempt =
        (error.requestOptions.extra['connection_retry'] as int?) ?? 0;
    if (!shouldRetryApiRequest(
      error.requestOptions.method,
      error.type,
      attempt,
    )) {
      handler.next(error);
      return;
    }

    await Future<void>.delayed(Duration(milliseconds: 650 * (attempt + 1)));
    try {
      final request = error.requestOptions;
      request.extra['connection_retry'] = attempt + 1;
      final response = await client.fetch<Object?>(request);
      handler.resolve(response);
    } on DioException catch (nextError) {
      handler.next(nextError);
    }
  }
}
