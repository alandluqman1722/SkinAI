import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skin_ai/medical_scan_api.dart';
import 'package:skin_ai/main.dart';

void main() {
  test('scan analysis sends the Firebase bearer token and save consent',
      () async {
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer firebase-id-token');
      expect(
        request.headers['content-type'],
        startsWith('multipart/form-data; boundary='),
      );
      expect(request.body, contains('name="save_history"'));
      expect(request.body, contains('\r\n\r\ntrue\r\n'));
      expect(request.body, isNot(contains('name="image_storage_consent"')));
      return http.Response(
        jsonEncode({
          'result': 'Provider result',
          'confidence': 0.75,
          'summary': 'Provider explanation.',
          'id': 'scan-1',
          'timestamp': '2026-04-04T10:00:00Z',
        }),
        200,
      );
    });

    final result = await SkinApi.analyze(
      'https://api.example.test',
      Uint8List.fromList([1, 2, 3]),
      'scan.jpg',
      idToken: 'firebase-id-token',
      saveHistory: true,
      client: client,
    );
    expect(result.scanId, 'scan-1');
    client.close();
  });

  test('lists authenticated owner-scoped scan records', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/medical/records/scans');
      expect(request.headers['authorization'], 'Bearer valid-firebase-token');
      return http.Response(
        jsonEncode([
          {
            'id': 'scan-1',
            'analysis_id': 'scan-1',
            'created_at': '2026-04-04T10:00:00Z',
            'result': 'Provider result',
            'confidence': 72.5,
            'explanation': 'Provider explanation.',
            'body_location': 'left cheek',
            'user_notes': 'User note.',
            'has_original_image': true,
          }
        ]),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = MedicalScanApi(
      baseUrl: 'https://api.example.test',
      idToken: 'valid-firebase-token',
      client: client,
    );

    final records = await api.listScans();
    expect(records, hasLength(1));
    expect(records.single.id, 'scan-1');
    expect(records.single.confidence, 72.5);
    expect(records.single.bodyLocation, 'left cheek');
    expect(records.single.hasOriginalImage, isTrue);
    client.close();
  });

  test('reports backend-managed private image storage as configured',
      () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/medical/integrations/status');
      return http.Response(
        jsonEncode({
          'medical_image_storage': {'configured': true},
        }),
        200,
      );
    });
    final api = MedicalScanApi(
      baseUrl: 'https://api.example.test',
      idToken: 'account-token',
      client: client,
    );

    expect(await api.originalImageStorageConfigured(), isTrue);
    client.close();
  });

  test('updates only user-editable scan metadata', () async {
    final client = MockClient((request) async {
      expect(request.method, 'PATCH');
      expect(request.url.path, '/medical/scans/scan%2F1');
      expect(request.headers['authorization'], 'Bearer account-token');
      expect(
        jsonDecode(request.body),
        {'body_location': 'right cheek', 'user_notes': 'Follow-up note.'},
      );
      return http.Response('{}', 200);
    });
    final api = MedicalScanApi(
      baseUrl: 'https://api.example.test',
      idToken: 'account-token',
      client: client,
    );

    await api.updateScan(
      scanId: 'scan/1',
      bodyLocation: 'right cheek',
      notes: 'Follow-up note.',
    );
    client.close();
  });

  test('requires server confirmation before considering a deletion complete',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'DELETE');
      expect(request.url.path, '/medical/records/scans/scan-1');
      return http.Response('not deleted', 503);
    });
    final api = MedicalScanApi(
      baseUrl: 'https://api.example.test',
      idToken: 'account-token',
      client: client,
    );

    await expectLater(
      api.deleteScan('scan-1'),
      throwsA(
        isA<MedicalScanApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          503,
        ),
      ),
    );
    client.close();
  });

  test('sends explicit consent with private original-image uploads', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/medical/scans/scan-1/original-image');
      expect(request.headers['authorization'], 'Bearer account-token');
      expect(
        request.headers['content-type'],
        startsWith('multipart/form-data; boundary='),
      );
      expect(request.body, contains('name="storage_consent"'));
      expect(request.body, contains('\r\n\r\ntrue\r\n'));
      expect(request.body, contains('name="file"; filename="scan.png"'));
      return http.Response('{"status":"stored"}', 201);
    });
    final api = MedicalScanApi(
      baseUrl: 'https://api.example.test',
      idToken: 'account-token',
      client: client,
    );

    var progressReported = false;
    await api.storeOriginalImage(
      scanId: 'scan-1',
      bytes: Uint8List.fromList([1, 2, 3]),
      filename: 'scan.png',
      onProgress: (sent, total) {
        expect(sent, lessThanOrEqualTo(total));
        progressReported = true;
      },
    );
    expect(progressReported, isTrue);
    client.close();
  });

  test('surfaces expired authentication without returning empty history',
      () async {
    final client = MockClient(
      (_) async => http.Response('{"detail":"expired"}', 401),
    );
    final api = MedicalScanApi(
      baseUrl: 'https://api.example.test',
      idToken: 'expired-token',
      client: client,
    );

    await expectLater(
      api.listScans(),
      throwsA(
        isA<MedicalScanApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          401,
        ),
      ),
    );
    client.close();
  });
}
