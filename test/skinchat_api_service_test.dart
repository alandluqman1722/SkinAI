import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skin_ai/skinchat/services/skinchat_api_service.dart';

void main() {
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
