import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:skin_ai/multipart_upload.dart';

class MedicalScanApiException implements Exception {
  const MedicalScanApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class MedicalScanRecord {
  const MedicalScanRecord({
    required this.id,
    required this.analysisId,
    required this.createdAt,
    required this.result,
    required this.confidence,
    required this.explanation,
    required this.hasOriginalImage,
    this.bodyLocation,
    this.notes,
  });

  final String id;
  final String analysisId;
  final DateTime createdAt;
  final String result;
  final double confidence;
  final String explanation;
  final String? bodyLocation;
  final String? notes;
  final bool hasOriginalImage;

  factory MedicalScanRecord.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final analysisId = json['analysis_id'];
    final createdAt = DateTime.tryParse(json['created_at'] as String? ?? '');
    final result = json['result'];
    final confidence = json['confidence'];
    final explanation = json['explanation'];
    if (id is! String ||
        analysisId is! String ||
        createdAt == null ||
        result is! String ||
        confidence is! num ||
        explanation is! String) {
      throw const MedicalScanApiException(
        'The medical scan service returned an invalid record.',
      );
    }
    return MedicalScanRecord(
      id: id,
      analysisId: analysisId,
      createdAt: createdAt.toLocal(),
      result: result,
      confidence: confidence.toDouble(),
      explanation: explanation,
      bodyLocation: json['body_location'] as String?,
      notes: json['user_notes'] as String?,
      hasOriginalImage: json['has_original_image'] == true,
    );
  }
}

class MedicalScanApi {
  MedicalScanApi({
    required String baseUrl,
    required this.idToken,
    http.Client? client,
  })  : _baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  final String _baseUrl;
  final String idToken;
  final http.Client _client;

  Uri _uri(String path) {
    final uri = Uri.tryParse('$_baseUrl$path');
    if (uri == null ||
        !uri.hasAuthority ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const MedicalScanApiException(
        'Configure a valid HTTP or HTTPS AI API URL.',
        statusCode: 400,
      );
    }
    if (idToken.trim().isEmpty) {
      throw const MedicalScanApiException(
        'A signed-in account is required to access scan history.',
        statusCode: 401,
      );
    }
    return uri;
  }

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Authorization': 'Bearer $idToken',
      };

  Future<bool> originalImageStorageConfigured() async {
    final response = await _request(
      'GET',
      '/medical/integrations/status',
    );
    final body = _decodeObject(response);
    final storage = body['medical_image_storage'];
    return storage is Map<String, dynamic> && storage['configured'] == true;
  }

  Future<List<MedicalScanRecord>> listScans() async {
    final response = await _request(
      'GET',
      '/medical/records/scans',
    );
    final decoded = _decodeJson(response);
    if (decoded is! List) {
      throw const MedicalScanApiException(
        'The medical scan service returned an invalid history response.',
      );
    }
    try {
      return decoded
          .map(
            (item) => MedicalScanRecord.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList()
        ..sort((first, second) => second.createdAt.compareTo(first.createdAt));
    } on MedicalScanApiException {
      rethrow;
    } on Object {
      throw const MedicalScanApiException(
        'The medical scan service returned an invalid history record.',
      );
    }
  }

  Future<void> updateScan({
    required String scanId,
    String? bodyLocation,
    String? notes,
  }) async {
    final response = await _request(
      'PATCH',
      '/medical/scans/${Uri.encodeComponent(scanId)}',
      body: {
        if (bodyLocation != null) 'body_location': bodyLocation,
        if (notes != null) 'user_notes': notes,
      },
    );
    if (response.statusCode != 200) {
      _throwForResponse(response);
    }
  }

  Future<void> deleteScan(String scanId) async {
    final response = await _request(
      'DELETE',
      '/medical/records/scans/${Uri.encodeComponent(scanId)}',
    );
    if (response.statusCode != 204) {
      _throwForResponse(response);
    }
  }

  Future<void> storeOriginalImage({
    required String scanId,
    required Uint8List bytes,
    required String filename,
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      throw const MedicalScanApiException(
        'The image must be between 1 byte and 10 MB.',
        statusCode: 413,
      );
    }
    final extension = filename.toLowerCase().split('.').last;
    final mediaType = switch (extension) {
      'png' => MediaType('image', 'png'),
      'webp' => MediaType('image', 'webp'),
      'gif' => MediaType('image', 'gif'),
      'bmp' => MediaType('image', 'bmp'),
      'tif' || 'tiff' => MediaType('image', 'tiff'),
      'jpg' || 'jpeg' => MediaType('image', 'jpeg'),
      _ => MediaType('application', 'octet-stream'),
    };
    final uri = _uri(
      '/medical/scans/${Uri.encodeComponent(scanId)}/original-image',
    );
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_headers)
      ..fields['storage_consent'] = 'true'
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
          contentType: mediaType,
        ),
      );
    try {
        final streamed = await sendMultipartWithProgress(
          _client,
          request,
          onProgress: onProgress,
        ).timeout(const Duration(seconds: 60));
        final response = await http.Response.fromStream(streamed)
            .timeout(const Duration(seconds: 60));
      if (response.statusCode != 201) {
        _throwForResponse(response);
      }
    } on MedicalScanApiException {
      rethrow;
    } on TimeoutException {
      throw const MedicalScanApiException(
        'Secure image storage request timed out.',
      );
    } on http.ClientException {
      throw const MedicalScanApiException(
        'Could not connect to secure image storage.',
      );
    }
  }

  Future<Uint8List> originalImage(String scanId) async {
    final response = await _request(
      'GET',
      '/medical/scans/${Uri.encodeComponent(scanId)}/original-image',
    );
    if (response.statusCode != 200) {
      _throwForResponse(response);
    }
    return response.bodyBytes;
  }

  Future<http.Response> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final uri = _uri(path);
    try {
      final response = switch (method) {
        'GET' => await _client
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 20)),
        'DELETE' => await _client
            .delete(uri, headers: _headers)
            .timeout(const Duration(seconds: 20)),
        'PATCH' => await _client
            .patch(
              uri,
              headers: {..._headers, 'Content-Type': 'application/json'},
              body: body == null ? null : _encode(body),
            )
            .timeout(const Duration(seconds: 20)),
        _ => throw ArgumentError.value(method, 'method'),
      };
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _throwForResponse(response);
      }
      return response;
    } on MedicalScanApiException {
      rethrow;
    } on http.ClientException {
      throw const MedicalScanApiException(
        'Could not connect to secure scan history.',
      );
    } on Exception {
      throw const MedicalScanApiException(
        'Could not connect to secure scan history.',
      );
    }
  }

  String _encode(Map<String, Object?> body) {
    return jsonEncode(body);
  }

  Object? _decodeJson(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const MedicalScanApiException(
        'The medical scan service returned an invalid response.',
      );
    }
  }

  Map<String, dynamic> _decodeObject(http.Response response) {
    final decoded = _decodeJson(response);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const MedicalScanApiException(
      'The medical scan service returned an invalid response.',
    );
  }

  Never _throwForResponse(http.Response response) {
    throw MedicalScanApiException(
      switch (response.statusCode) {
        401 => 'Your session expired. Sign in again to access scan history.',
        403 => 'Access to this scan record was denied.',
        404 => 'The scan record was not found.',
        409 => 'This scan record cannot be changed.',
        413 => 'The image exceeds the upload limit.',
        503 => 'Secure scan history or image storage is unavailable.',
        _ => 'Secure scan history request failed.',
      },
      statusCode: response.statusCode,
    );
  }
}
