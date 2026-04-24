import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'api_client.dart';

class ImageUploadAsset {
  const ImageUploadAsset({
    required this.id,
    required this.kind,
    required this.mimeType,
    this.url,
  });

  final String id;
  final String kind;
  final String mimeType;
  final String? url;

  factory ImageUploadAsset.fromJson(
    Map<String, dynamic> json, {
    String? Function(String?)? resolveUrl,
  }) {
    return ImageUploadAsset(
      id: json['id'] as String? ?? '',
      kind: json['kind'] as String? ?? '',
      mimeType: json['mimeType'] as String? ?? '',
      url: _resolveUrl(json['url'], resolveUrl),
    );
  }
}

class ImageUploadTarget {
  const ImageUploadTarget({
    required this.method,
    required this.url,
    required this.headers,
  });

  final String method;
  final String url;
  final Map<String, String> headers;

  factory ImageUploadTarget.fromJson(Map<String, dynamic> json) {
    final rawHeaders = json['headers'] as Map<String, dynamic>? ?? const {};
    return ImageUploadTarget(
      method: json['method'] as String? ?? 'PUT',
      url: json['url'] as String? ?? '',
      headers: rawHeaders.map(
        (key, value) => MapEntry(key, value?.toString() ?? ''),
      ),
    );
  }
}

class ImageUploadIssueResponse {
  const ImageUploadIssueResponse({required this.asset, required this.upload});

  final ImageUploadAsset asset;
  final ImageUploadTarget upload;

  factory ImageUploadIssueResponse.fromJson(
    Map<String, dynamic> json, {
    String? Function(String?)? resolveUrl,
  }) {
    return ImageUploadIssueResponse(
      asset: ImageUploadAsset.fromJson(
        json['asset'] as Map<String, dynamic>? ?? const {},
        resolveUrl: resolveUrl,
      ),
      upload: ImageUploadTarget.fromJson(
        json['upload'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}

class AssetsRepository {
  const AssetsRepository({required this.apiClient});

  final ApiClient apiClient;

  Future<ImageUploadIssueResponse> createImageUpload({
    required String fileName,
    required String mimeType,
  }) async {
    final response = await apiClient.post(
      '/assets/uploads',
      body: {'fileName': fileName, 'mimeType': mimeType},
    );
    return ImageUploadIssueResponse.fromJson(
      response,
      resolveUrl: apiClient.resolveUrl,
    );
  }

  Future<void> uploadIssuedImage({
    required ImageUploadTarget target,
    required Uint8List bytes,
  }) async {
    await apiClient.putBytesAbsolute(
      target.url,
      body: bytes,
      headers: target.headers,
    );
  }

  Future<ImageUploadAsset> completeImageUpload(String assetId) async {
    final response = await apiClient.post('/assets/$assetId/complete');
    return ImageUploadAsset.fromJson(
      response,
      resolveUrl: apiClient.resolveUrl,
    );
  }

  Future<ImageUploadAsset> uploadImage({
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(apiClient.resolveUrl('/assets/images')!),
    );
    final authToken = apiClient.authToken;
    if (authToken != null && authToken.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $authToken';
    }
    request.fields['fileName'] = fileName;
    request.fields['mimeType'] = mimeType;
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: fileName),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    final body = _decodeJson(response.body);
    if (response.statusCode >= 400) {
      throw ApiException(
        statusCode: response.statusCode,
        message:
            (body['message'] as String?) ??
            response.reasonPhrase ??
            'Image upload failed',
        body: body,
      );
    }
    return ImageUploadAsset.fromJson(body, resolveUrl: apiClient.resolveUrl);
  }
}

String? _resolveUrl(Object? value, String? Function(String?)? resolveUrl) {
  final raw = value as String?;
  return resolveUrl?.call(raw) ?? raw;
}

Map<String, dynamic> _decodeJson(String body) {
  if (body.trim().isEmpty) {
    return <String, dynamic>{};
  }
  try {
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  } catch (_) {
    return <String, dynamic>{};
  }
}
