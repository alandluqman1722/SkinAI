import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skin_ai/skinchat/models/skinchat_models.dart';
import 'package:skin_ai/skinchat/services/skinchat_api_service.dart';

void main() {
  test('sendMessage posts the supported payload and parses its reply',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/api/skinchat/conversations/conversation-1/messages',
      );
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['content'], 'Why does my skin become dry?');
      expect(body['client_message_id'], 'message-1');
      expect(body['language'], 'en');
      return _jsonResponse({
        'message': _message('user-message', 'user', body['content'] as String),
        'reply': _message('assistant-message', 'assistant', 'A useful answer.'),
      });
    });
    final service = SkinChatApiService(
      baseUrl: 'http://localhost:8000',
      idTokenProvider: () async => 'test-token',
      client: client,
    );

    final (message, reply) = await service.sendMessage(
      'conversation-1',
      'Why does my skin become dry?',
      clientMessageId: 'message-1',
      language: 'en',
    );

    expect(message.role, 'user');
    expect(reply.content, 'A useful answer.');
    client.close();
  });

  test('createConversation sends scan context as JSON metadata', () async {
    final scanContext = SkinChatScanContext(
      scanId: 'scan-123',
      detectedCondition: 'screening-result',
      confidence: 72.5,
      scanDate: DateTime.utc(2026, 11, 16),
      summary: 'Screening summary.',
      hasOriginalImage: false,
    );
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['scan_context']['scan_id'], 'scan-123');
      return _jsonResponse({
        'conversation_id': 'conversation-1',
        'created_at': '2026-11-16T10:00:00Z',
        'updated_at': '2026-11-16T10:00:00Z',
        'scan_context': scanContext.toJson(),
      });
    });
    final service = SkinChatApiService(
      baseUrl: 'http://localhost:8000',
      idTokenProvider: () async => 'test-token',
      client: client,
    );

    final conversation = await service.createConversation(
      scanContext: scanContext,
    );

    expect(conversation.scanContext?.scanId, 'scan-123');
    client.close();
  });

  test('invalid message response is surfaced as a friendly API exception',
      () async {
    final client = MockClient((_) async => http.Response('[]', 200));
    final service = SkinChatApiService(
      baseUrl: 'http://localhost:8000',
      idTokenProvider: () async => 'test-token',
      client: client,
    );

    await expectLater(
      service.sendMessage(
        'conversation-1',
        'Why does my skin become dry?',
        clientMessageId: 'message-1',
        language: 'en',
      ),
      throwsA(
        isA<SkinChatApiException>().having(
          (error) => error.message,
          'message',
          contains('invalid response'),
        ),
      ),
    );
    client.close();
  });

  test('message timeout is surfaced as retryable without raw exception text',
      () async {
    final client = MockClient((_) => Completer<http.Response>().future);
    final service = SkinChatApiService(
      baseUrl: 'http://localhost:8000',
      idTokenProvider: () async => 'test-token',
      client: client,
      requestTimeout: const Duration(milliseconds: 10),
    );

    try {
      await service.sendMessage(
        'conversation-1',
        'How can I care for dry skin?',
        clientMessageId: 'message-1',
        language: 'en',
      );
      fail('Expected the request to time out.');
    } on SkinChatApiException catch (error) {
      expect(error.statusCode, 408);
      expect(error.message, contains('Retry the same message'));
      expect(error.message, isNot(contains('TimeoutException')));
    } finally {
      client.close();
    }
  });
}

Map<String, Object?> _message(String id, String role, String content) => {
      'message_id': id,
      'role': role,
      'content': content,
      'language': 'en',
      'created_at': '2026-11-16T10:00:00Z',
    };

http.Response _jsonResponse(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
