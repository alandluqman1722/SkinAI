import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skin_ai/skinchat/screens/skinchat_screen.dart';
import 'package:skin_ai/skinchat/services/skinchat_api_service.dart';

void main() {
  testWidgets('wide SkinChat content is centered and width constrained',
      (tester) async {
    _setViewport(tester, const Size(1440, 900));
    addTearDown(_resetViewport(tester));
    final client = _chatClient();
    final api = SkinChatApiService(
      baseUrl: 'http://localhost:8000',
      idTokenProvider: () async => 'test-token',
      client: client,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SkinChatScreen(
          baseUrl: 'http://localhost:8000',
          languageCode: 'en',
          api: api,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final contentRect =
        tester.getRect(find.byKey(const ValueKey('skinchat-content')));
    expect(contentRect.width, 1200);
    expect(tester.widgetList<MarkdownBody>(find.byType(MarkdownBody)),
        hasLength(2));
    expect(
      tester
          .widget<Align>(
            find.byKey(const ValueKey('skinchat-message-assistant-1')),
          )
          .alignment,
      AlignmentDirectional.centerStart,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('SkinChat bubbles and controls remain usable in Kurdish RTL',
      (tester) async {
    _setViewport(tester, const Size(320, 568));
    addTearDown(_resetViewport(tester));
    final client = _chatClient();
    final api = SkinChatApiService(
      baseUrl: 'http://localhost:8000',
      idTokenProvider: () async => 'test-token',
      client: client,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(1.2),
          ),
          child: SkinChatScreen(
            baseUrl: 'http://localhost:8000',
            languageCode: 'ku',
            api: api,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final contentContext =
        tester.element(find.byKey(const ValueKey('skinchat-content')));
    expect(Directionality.of(contentContext), TextDirection.rtl);
    await tester.drag(find.byType(ListView).first, const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Align>(
            find.byKey(const ValueKey('skinchat-message-user-1')),
          )
          .alignment,
      AlignmentDirectional.centerEnd,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });
}

MockClient _chatClient() => MockClient((request) async {
      if (request.url.path == '/api/skinchat/conversations') {
        return _jsonResponse([
          {
            'conversation_id': 'conversation-1',
            'created_at': '2025-01-01T10:00:00Z',
            'updated_at': '2025-01-01T10:00:00Z',
            'image_available': false,
          },
        ]);
      }
      if (request.url.path.endsWith('/messages')) {
        return _jsonResponse({
          'messages': [
            {
              'message_id': 'user-1',
              'role': 'user',
              'content': '**پرسیار**\n\nپرسیارەکەم',
              'language': 'ku',
              'created_at': '2025-01-01T10:00:00Z',
            },
            {
              'message_id': 'assistant-1',
              'role': 'assistant',
              'content': '# وەڵام\n\n**ئاوی پێست**',
              'language': 'ku',
              'created_at': '2025-01-01T10:00:01Z',
            },
          ],
          'next_before': null,
        });
      }
      return http.Response('', 404);
    });

http.Response _jsonResponse(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void _setViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
}

void Function() _resetViewport(WidgetTester tester) => () {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    };
