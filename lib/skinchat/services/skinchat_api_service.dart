import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:skin_ai/multipart_upload.dart';
import 'package:skin_ai/skinchat/models/skinchat_models.dart';

typedef FirebaseIdTokenProvider = Future<String?> Function();

class SkinChatApiException implements Exception {
  const SkinChatApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class SkinChatApiService {
  SkinChatApiService({
    required String baseUrl,
    required FirebaseIdTokenProvider idTokenProvider,
    http.Client? client,
    Duration requestTimeout = const Duration(seconds: 105),
  })  : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _idTokenProvider = idTokenProvider,
        _client = client ?? http.Client(),
        _requestTimeout = requestTimeout;

  final String _baseUrl;
  final FirebaseIdTokenProvider _idTokenProvider;
  final http.Client _client;
  final Duration _requestTimeout;

  String get _conversationsUrl => '$_baseUrl/api/skinchat/conversations';

  Future<Map<String, String>> _headers() async {
    final token = await _idTokenProvider();
    if (token == null || token.isEmpty) {
      throw const SkinChatApiException(
        'Your sign-in session has expired. Sign in again.',
        statusCode: 401,
      );
    }
    return {'Authorization': 'Bearer $token'};
  }

  Future<http.Response> _request(
    Future<http.Response> Function(Map<String, String> headers) request,
  ) async {
    try {
      final response = await request(await _headers()).timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SkinChatApiException(
          _errorMessage(response),
          statusCode: response.statusCode,
        );
      }
      return response;
    } on SkinChatApiException {
      rethrow;
    } on TimeoutException {
      throw const SkinChatApiException(
        'The request timed out. Retry the same message to check for a saved reply.',
        statusCode: 408,
      );
    } on Object {
      throw const SkinChatApiException(
        'Could not connect to SkinChat. Check your connection and retry.',
      );
    }
  }

  String _errorMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final detail = body['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
    } on FormatException {
      // Use the status code when the server does not return JSON.
    } on TypeError {
      // Use the status code when the error payload has an unexpected shape.
    }
    return 'SkinChat request failed (${response.statusCode}).';
  }

  T _parseResponse<T>(T Function() parse) {
    try {
      return parse();
    } on SkinChatApiException {
      rethrow;
    } on Object {
      throw const SkinChatApiException(
        'The SkinChat server returned an invalid response.',
      );
    }
  }

  Map<String, dynamic> _decodeObject(http.Response response) =>
      _parseResponse(() {
        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Expected an object.');
        }
        return decoded;
      });

  Future<SkinChatConversation> createConversation({
    SkinChatScanContext? scanContext,
  }) async {
    final response = await _request(
      (headers) => _client.post(
        Uri.parse(_conversationsUrl),
        headers: scanContext == null
            ? headers
            : {...headers, 'Content-Type': 'application/json'},
        body: scanContext == null
            ? null
            : jsonEncode({'scan_context': scanContext.toJson()}),
      ),
    );
    return _parseResponse(
      () => SkinChatConversation.fromJson(_decodeObject(response)),
    );
  }

  Future<List<SkinChatConversation>> listConversations() async {
    final response = await _request(
      (headers) => _client.get(
        Uri.parse(_conversationsUrl),
        headers: headers,
      ),
    );
    return _parseResponse(() {
      final decoded = jsonDecode(response.body);
      if (decoded is! List<dynamic>) {
        throw const FormatException('Expected a list.');
      }
      return decoded
          .map(
            (item) => SkinChatConversation.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    });
  }

  Future<SkinChatMessagesPage> getMessages(
    String conversationId, {
    String? before,
  }) async {
    final uri = Uri.parse(
      '$_conversationsUrl/${Uri.encodeComponent(conversationId)}/messages',
    ).replace(
      queryParameters: {
        'limit': '50',
        if (before != null) 'before': before,
      },
    );
    final response = await _request(
      (headers) => _client.get(uri, headers: headers),
    );
    return _parseResponse(
      () => SkinChatMessagesPage.fromJson(_decodeObject(response)),
    );
  }

  Future<SkinChatConversation> uploadImage(String conversationId, XFile file,
      {required String language,
      void Function(int sentBytes, int totalBytes)? onProgress}) async {
    final uri = Uri.parse(
      '$_conversationsUrl/${Uri.encodeComponent(conversationId)}/image',
    );
    try {
      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(await _headers())
        ..fields['language'] = language
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            await file.readAsBytes(),
            filename: file.name,
            contentType: _contentType(file),
          ),
        );
      final streamed = await sendMultipartWithProgress(
        _client,
        request,
        onProgress: onProgress,
      ).timeout(_requestTimeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SkinChatApiException(
          _errorMessage(response),
          statusCode: response.statusCode,
        );
      }
      final data = _decodeObject(response);
      final uploadedImageId = data['uploaded_image_id'];
      final imageUploadTimestamp = data['image_upload_timestamp'];
      if (uploadedImageId is! String || imageUploadTimestamp is! String) {
        throw const SkinChatApiException(
          'The SkinChat server returned an invalid image response.',
        );
      }
      final updated = await getConversation(conversationId);
      return updated.copyWith(
        uploadedImageId: uploadedImageId,
        imageUploadTimestamp: DateTime.tryParse(imageUploadTimestamp),
        initialAnalysis: data['initial_analysis'] as String?,
        detectedLanguage: data['detected_language'] as String? ?? 'en',
      );
    } on SkinChatApiException {
      rethrow;
    } on Object {
      throw const SkinChatApiException(
        'Image upload failed. Check your connection and retry.',
      );
    }
  }

  MediaType _contentType(XFile file) {
    final type = file.mimeType;
    if (type != null && type.startsWith('image/')) {
      return MediaType.parse(type);
    }
    final extension = file.name.split('.').last.toLowerCase();
    return switch (extension) {
      'png' => MediaType('image', 'png'),
      'webp' => MediaType('image', 'webp'),
      _ => MediaType('image', 'jpeg'),
    };
  }

  Future<SkinChatConversation> getConversation(String conversationId) async {
    final response = await _request(
      (headers) => _client.get(
        Uri.parse(
          '$_conversationsUrl/${Uri.encodeComponent(conversationId)}',
        ),
        headers: headers,
      ),
    );
    return _parseResponse(
      () => SkinChatConversation.fromJson(_decodeObject(response)),
    );
  }

  Future<(SkinChatMessage, SkinChatMessage)> sendMessage(
    String conversationId,
    String content, {
    required String clientMessageId,
    required String language,
  }) async {
    final response = await _request(
      (headers) => _client.post(
        Uri.parse(
          '$_conversationsUrl/${Uri.encodeComponent(conversationId)}/messages',
        ),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'content': content,
          'client_message_id': clientMessageId,
          'language': language,
        }),
      ),
    );
    return _parseResponse(() {
      final data = _decodeObject(response);
      final message = data['message'];
      final reply = data['reply'];
      if (message is! Map || reply is! Map) {
        throw const FormatException('Expected message and reply objects.');
      }
      return (
        SkinChatMessage.fromJson(Map<String, dynamic>.from(message)),
        SkinChatMessage.fromJson(Map<String, dynamic>.from(reply)),
      );
    });
  }

  Future<Uint8List> getImage(String conversationId) async {
    final response = await _request(
      (headers) => _client.get(
        Uri.parse(
          '$_conversationsUrl/${Uri.encodeComponent(conversationId)}/image',
        ),
        headers: headers,
      ),
    );
    return response.bodyBytes;
  }

  Future<void> deleteConversation(String conversationId) async {
    await _request(
      (headers) => _client.delete(
        Uri.parse(
          '$_conversationsUrl/${Uri.encodeComponent(conversationId)}',
        ),
        headers: headers,
      ),
    );
  }

  Future<void> deleteMessage(String conversationId, String messageId) async {
    await _request(
      (headers) => _client.delete(
        Uri.parse(
          '$_conversationsUrl/${Uri.encodeComponent(conversationId)}'
          '/messages/${Uri.encodeComponent(messageId)}',
        ),
        headers: headers,
      ),
    );
  }
}
