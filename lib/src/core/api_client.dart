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
            defaultValue: 'https://slktegy.com/api/v1',
          ),
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 35),
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        ),
      );

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

  Future<Map<String, dynamic>> delete(String path, {String? audience}) =>
      _request('DELETE', path, audience: audience);

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
        message = 'Cannot reach SLKT. Check your connection and try again.';
      }
      throw ApiException(
        message,
        statusCode: response?.statusCode,
        fields: fields,
      );
    }
  }
}
