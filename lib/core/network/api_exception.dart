import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// A failure the UI can show a person.
///
/// Every backend error arrives in one envelope:
/// `{"error": {"code": "...", "message": "...", "details": [...]}}`
/// so this parses it once instead of at every call site.
class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.fieldErrors = const {},
  });

  /// Builds from a backend response body.
  factory ApiException.fromResponse(int statusCode, dynamic body) {
    if (body is Map<String, dynamic> && body['error'] is Map<String, dynamic>) {
      final error = body['error'] as Map<String, dynamic>;

      final fieldErrors = <String, String>{};
      final details = error['details'];
      if (details is List) {
        for (final detail in details) {
          if (detail is Map<String, dynamic>) {
            final field = detail['field'];
            final message = detail['message'];
            if (field is String && message is String) {
              fieldErrors[field] = message;
            }
          }
        }
      }

      return ApiException(
        statusCode: statusCode,
        code: error['code'] as String? ?? 'unknown_error',
        message: error['message'] as String? ?? 'Something went wrong',
        fieldErrors: fieldErrors,
      );
    }

    return ApiException(
      statusCode: statusCode,
      code: 'unexpected_response',
      message: 'The server returned an unexpected response',
    );
  }

  /// Builds from a transport failure - no response was ever received.
  factory ApiException.network(DioException error) {
    final message = switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        'The server took too long to respond',
      DioExceptionType.connectionError =>
        'Could not reach the server. Check your connection.',
      _ => 'Something went wrong. Please try again.',
    };

    // In debug builds, name the address that failed. Without it every
    // misconfiguration looks identical, and the most common one - forgetting
    // --dart-define, so the app silently falls back to the emulator-only
    // 10.0.2.2 - is indistinguishable from a firewall or a stopped server.
    // Release builds show the plain message; users cannot act on a URL.
    final detail = kDebugMode ? '\n${error.requestOptions.uri}' : '';

    return ApiException(
      statusCode: 0,
      code: 'network_error',
      message: '$message$detail',
    );
  }

  final int statusCode;
  final String code;
  final String message;

  /// Per-field validation messages, keyed by field name.
  final Map<String, String> fieldErrors;

  bool get isUnauthorized => statusCode == 401;
  bool get isNetworkFailure => statusCode == 0;

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}
