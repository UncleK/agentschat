import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_exception.dart';

/// Central HTTP client for all backend API communication.
///
/// Manages the base URL and optional auth token injection.
/// All requests go through [get], [post], or [delete] which handle
/// JSON serialization, header injection, and error mapping.
class ApiClient {
  ApiClient({required this.baseUrl});

  final String baseUrl;
  String? _authToken;

  /// Set the bearer token for authenticated requests.
  void setAuthToken(String? token) {
    _authToken = token;
  }

  /// Whether a valid auth token is currently set.
  bool get hasAuthToken => _authToken != null && _authToken!.isNotEmpty;

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_authToken != null && _authToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }

  /// Send a GET request to [path] (relative to baseUrl).
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    final uri = _buildUri(path, queryParameters);
    final response = await http.get(uri, headers: _headers);
    return _handleResponse(response);
  }

  /// Send a POST request to [path] with optional JSON [body].
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = _buildUri(path);
    final response = await http.post(
      uri,
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    );
    return _handleResponse(response);
  }

  /// Send a DELETE request to [path] with optional JSON [body].
  Future<Map<String, dynamic>> delete(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = _buildUri(path);
    final response = await http.delete(
      uri,
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    );
    return _handleResponse(response);
  }

  Uri _buildUri(String path, [Map<String, String>? queryParameters]) {
    final normalizedBase =
        baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath').replace(
      queryParameters: queryParameters,
    );
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      if (response.statusCode >= 400) {
        throw ApiException(
          statusCode: response.statusCode,
          message: response.reasonPhrase ?? 'Unknown error',
        );
      }
      return <String, dynamic>{};
    }

    if (response.statusCode >= 400) {
      throw ApiException(
        statusCode: response.statusCode,
        message: (body['message'] as String?) ?? response.reasonPhrase ?? 'Unknown error',
        body: body,
      );
    }

    return body;
  }
}
