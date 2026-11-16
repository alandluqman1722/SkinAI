import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skin_ai/skinchat/screens/skinchat_screen.dart';
import 'package:skin_ai/skinchat/models/skinchat_models.dart';
import 'package:skin_ai/skinchat/services/skinchat_api_service.dart';

void main() {
  testWidgets('general questions send and show a reply without an image',
      (tester) async {
    final replyCompleter = Completer<http.Response>();
    final client = MockClient((request) async {
      if (request.url.path == '/api/skinchat/conversations' &&
          request.method == 'GET') {
        return _jsonResponse([]);
      }
      if (request.url.path == '/api/skinchat/conversations' &&
          request.method == 'POST') {
        return _jsonResponse({
          'conversation_id': 'conversation-1',
          'created_at': '2026-11-16T10:00:00Z',
          'updated_at': '2026-11-16T10:00:00Z',
          'image_available': false,
        });
      }
      if (request.url.path.endsWith('/messages') &&
          request.method == 'GET') {
        return _jsonResponse({'messages': [], 'next_before': null});
      }
      if (request.url.path.endsWith('/messages') &&
          request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['content'], 'Why does my skin become dry?');
        return replyCompleter.future;
      }
      return http.Response('', 404);
    });
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

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.enabled, isTrue);
    expect(find.textContaining('No scan is attached.'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField),
      'Why does my skin become dry?',
    );
    await tester.tap(find.byTooltip('Send message'));
    await tester.pump();

    expect(find.text('Why does my skin become dry?'), findsOneWidget);
    expect(find.text('SkinChat is responding…'), findsOneWidget);
    replyCompleter.complete(
      _jsonResponse({
        'message': {
          'message_id': 'user-message-1',
          'role': 'user',
          'content': 'Why does my skin become dry?',
          'language': 'en',
          'created_at': '2026-11-16T10:00:01Z',
        },
        'reply': {
          'message_id': 'assistant-message-1',
          'role': 'assistant',
          'content': 'Dryness can have several causes.',
          'language': 'en',
          'created_at': '2026-11-16T10:00:02Z',
        },
      }),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dryness can have several causes.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('failed message retry reuses the pending message',
      (tester) async {
    final messageIds = <String>[];
    var sendAttempts = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/skinchat/conversations' &&
          request.method == 'GET') {
        return _jsonResponse([]);
      }
      if (request.url.path == '/api/skinchat/conversations' &&
          request.method == 'POST') {
        return _jsonResponse({
          'conversation_id': 'conversation-1',
          'created_at': '2026-11-16T10:00:00Z',
          'updated_at': '2026-11-16T10:00:00Z',
          'image_available': false,
        });
      }
      if (request.url.path.endsWith('/messages') &&
          request.method == 'GET') {
        return _jsonResponse({'messages': [], 'next_before': null});
      }
      if (request.url.path.endsWith('/messages') &&
          request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        messageIds.add(body['client_message_id'] as String);
        sendAttempts++;
        if (sendAttempts == 1) {
          return _jsonResponse(
            {'detail': 'The provider is temporarily unavailable.'},
            statusCode: 503,
          );
        }
        return _jsonResponse({
          'message': {
            'message_id': 'user-retry-1',
            'role': 'user',
            'content': body['content'],
            'language': 'en',
            'created_at': '2026-11-16T10:00:01Z',
          },
          'reply': {
            'message_id': 'assistant-retry-1',
            'role': 'assistant',
            'content': 'Retry succeeded.',
            'language': 'en',
            'created_at': '2026-11-16T10:00:02Z',
          },
        });
      }
      return http.Response('', 404);
    });
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
    await tester.enterText(
      find.byType(TextField),
      'Why does my skin become dry?',
    );
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();

    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Why does my skin become dry?'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(messageIds, hasLength(2));
    expect(messageIds[0], messageIds[1]);
    expect(find.text('Retry succeeded.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('latest scan metadata is attached to a SkinChat conversation',
      (tester) async {
    final imageData = await rootBundle.load('assets/icon/logo.png');
    final imageBytes = imageData.buffer.asUint8List(
      imageData.offsetInBytes,
      imageData.lengthInBytes,
    );
    final scanContext = SkinChatScanContext(
      scanId: 'scan-123',
      detectedCondition: 'screening-result',
      confidence: 72.5,
      scanDate: DateTime.utc(2026, 11, 16),
      summary: 'Screening summary.',
      bodyLocation: 'left arm',
    );
    var chatImageUploadRequested = false;
    final client = MockClient((request) async {
      if (request.url.path == '/api/skinchat/conversations' &&
          request.method == 'GET') {
        return _jsonResponse([]);
      }
      if (request.url.path == '/api/skinchat/conversations' &&
          request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final attachedContext =
            body['scan_context'] as Map<String, dynamic>;
        expect(attachedContext['scan_id'], 'scan-123');
        return _jsonResponse({
          'conversation_id': 'conversation-scan',
          'created_at': '2026-11-16T10:00:00Z',
          'updated_at': '2026-11-16T10:00:00Z',
          'image_available': false,
          'scan_context': attachedContext,
        });
      }
      if (request.url.path.endsWith('/messages')) {
        return _jsonResponse({'messages': [], 'next_before': null});
      }
      if (request.url.path.endsWith('/image')) {
        chatImageUploadRequested = true;
      }
      return http.Response('', 404);
    });
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
          scanContext: scanContext,
          scanImageBytes: imageBytes,
          api: api,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Scan ID: scan-123'), findsOneWidget);
    expect(find.text('Detected result: screening-result'), findsOneWidget);
    expect(find.text('Model confidence: 72.5%'), findsOneWidget);
    final preview = tester.widget<Image>(find.byType(Image).first);
    expect(
      (preview.image as MemoryImage).bytes,
      orderedEquals(imageBytes),
    );
    expect(chatImageUploadRequested, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

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

http.Response _jsonResponse(Object body, {int statusCode = 200}) => http.Response(
      jsonEncode(body),
      statusCode,
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
