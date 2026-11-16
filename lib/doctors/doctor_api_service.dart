import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

import 'doctor_models.dart';

typedef DoctorIdTokenProvider = Future<String?> Function();

class DoctorApiException implements Exception {
  const DoctorApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class DoctorApiService {
  DoctorApiService({
    required String baseUrl,
    required DoctorIdTokenProvider idTokenProvider,
    http.Client? client,
  })  : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _idTokenProvider = idTokenProvider,
        _client = client ?? http.Client();

  final String _baseUrl;
  final DoctorIdTokenProvider _idTokenProvider;
  final http.Client _client;
  String get baseUrl => _baseUrl;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$_baseUrl/api/doctors$path').replace(queryParameters: query);

  Future<Map<String, String>> _headers({required bool authenticated}) async {
    final token = await _idTokenProvider();
    if (authenticated && (token == null || token.isEmpty)) {
      throw const DoctorApiException(
        'Sign in to use favorites, appointments, and reviews.',
        statusCode: 401,
      );
    }
    return {
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool authenticated = true,
  }) async {
    try {
      final headers = await _headers(authenticated: authenticated);
      final uri = _uri(path, query);
      final response = switch (method) {
        'GET' => await _client.get(uri, headers: headers).timeout(
              const Duration(seconds: 45),
            ),
        'POST' => await _client
            .post(
              uri,
              headers: {
                ...headers,
                if (body != null) 'Content-Type': 'application/json',
              },
              body: body == null ? null : jsonEncode(body),
            )
            .timeout(const Duration(seconds: 105)),
        'PUT' => await _client
            .put(
              uri,
              headers: {
                ...headers,
                if (body != null) 'Content-Type': 'application/json',
              },
              body: body == null ? null : jsonEncode(body),
            )
            .timeout(const Duration(seconds: 45)),
        'PATCH' => await _client
            .patch(
              uri,
              headers: {
                ...headers,
                if (body != null) 'Content-Type': 'application/json',
              },
              body: body == null ? null : jsonEncode(body),
            )
            .timeout(const Duration(seconds: 45)),
        'DELETE' => await _client.delete(uri, headers: headers).timeout(
              const Duration(seconds: 45),
            ),
        _ => throw ArgumentError.value(method, 'method'),
      };
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw DoctorApiException(
          _errorMessage(response),
          statusCode: response.statusCode,
        );
      }
      if (response.bodyBytes.isEmpty) return null;
      try {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        throw const DoctorApiException(
          'The doctor directory returned an invalid response.',
        );
      }
    } on DoctorApiException {
      rethrow;
    } on TimeoutException {
      throw const DoctorApiException(
        'The request took too long. Check your connection and retry.',
        statusCode: 408,
      );
    } on Exception {
      throw const DoctorApiException(
        'Could not connect to the doctor directory. Check your connection and retry.',
      );
    }
  }

  String _errorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(
          response.bodyBytes.isEmpty ? '{}' : utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic> &&
          decoded['detail'] is String &&
          (decoded['detail'] as String).isNotEmpty) {
        return decoded['detail'] as String;
      }
    } on FormatException {
      // The status code is enough when the server does not return JSON.
    }
    return 'Doctor directory request failed (${response.statusCode}).';
  }

  List<dynamic> _list(Object? value) {
    if (value is List<dynamic>) return value;
    throw const DoctorApiException(
      'The doctor directory returned an invalid list.',
    );
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    throw const DoctorApiException(
      'The doctor directory returned an invalid record.',
    );
  }

  Future<List<DoctorProfile>> listDoctors({
    String search = '',
    String city = '',
    String specialization = '',
    String clinic = '',
    int? availableWithinDays,
    String sort = 'rating',
  }) async {
    final query = <String, String>{
      if (search.trim().isNotEmpty) 'search': search.trim(),
      if (city.isNotEmpty) 'city': city,
      if (specialization.isNotEmpty) 'specialization': specialization,
      if (clinic.trim().isNotEmpty) 'clinic': clinic.trim(),
      if (availableWithinDays != null)
        'available_within_days': '$availableWithinDays',
      'sort': sort,
    };
    final data = _list(
      await _request('GET', '', query: query, authenticated: false),
    );
    return [
      for (final item in data)
        DoctorProfile.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
  }

  Future<DoctorProfile> getDoctor(String doctorId) async =>
      DoctorProfile.fromJson(
        _map(
          await _request(
            'GET',
            '/${Uri.encodeComponent(doctorId)}',
            authenticated: false,
          ),
        ),
      );

  Future<List<DoctorProfile>> listFavorites() async {
    final data = _list(await _request('GET', '/favorites/mine'));
    return [
      for (final item in data)
        DoctorProfile.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
  }

  Future<bool> isFavorite(String doctorId) async {
    final data = _map(
      await _request(
        'GET',
        '/${Uri.encodeComponent(doctorId)}/favorite',
      ),
    );
    return data['is_favorite'] == true;
  }

  Future<bool> setFavorite(String doctorId, bool favorite) async {
    final data = _map(
      await _request(
        favorite ? 'PUT' : 'DELETE',
        '/${Uri.encodeComponent(doctorId)}/favorite',
      ),
    );
    return data['is_favorite'] == true;
  }

  Future<List<DoctorReview>> listReviews(String doctorId) async {
    final data = _list(
      await _request(
        'GET',
        '/${Uri.encodeComponent(doctorId)}/reviews',
        authenticated: false,
      ),
    );
    return [
      for (final item in data)
        DoctorReview.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
  }

  Future<List<String>> availableTimes({
    required String doctorId,
    required String clinicId,
    required DateTime date,
  }) async {
    final data = _map(
      await _request(
        'GET',
        '/${Uri.encodeComponent(doctorId)}/availability',
        query: {
          'clinic_id': clinicId,
          'date': _dateOnly(date),
        },
        authenticated: false,
      ),
    );
    return [
      for (final item in data['times'] as List? ?? const [])
        if (item is String) item,
    ];
  }

  Future<List<DoctorAppointment>> listAppointments() async {
    final data = _list(await _request('GET', '/appointments'));
    return [
      for (final item in data)
        DoctorAppointment.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
  }

  Future<DoctorAppointment> bookAppointment({
    required String doctorId,
    required String clinicId,
    required DateTime date,
    required String time,
  }) async =>
      DoctorAppointment.fromJson(
        _map(
          await _request(
            'POST',
            '/appointments',
            body: {
              'doctor_id': doctorId,
              'clinic_id': clinicId,
              'appointment_date': _dateOnly(date),
              'appointment_time': time,
            },
          ),
        ),
      );

  Future<DoctorAppointment> cancelAppointment(String appointmentId) async =>
      DoctorAppointment.fromJson(
        _map(
          await _request(
            'POST',
            '/appointments/${Uri.encodeComponent(appointmentId)}/cancel',
          ),
        ),
      );

  Future<void> submitReview({
    required String appointmentId,
    required int rating,
    required String comment,
  }) async {
    await _request(
      'POST',
      '/appointments/${Uri.encodeComponent(appointmentId)}/review',
      body: {
        'appointment_id': appointmentId,
        'rating': rating,
        'comment': comment,
      },
    );
  }

  Future<void> reportReview({
    required String doctorId,
    required String reviewId,
    required String reason,
  }) async {
    await _request(
      'POST',
      '/${Uri.encodeComponent(doctorId)}/reviews/'
          '${Uri.encodeComponent(reviewId)}/report',
      body: {'reason': reason},
    );
  }

  Future<List<DoctorProfile>> listAdminDoctors() async {
    final data = _list(await _request('GET', '/admin/doctors'));
    return [
      for (final item in data)
        DoctorProfile.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
  }

  Future<DoctorProfile> saveDoctor(
    DoctorProfile doctor, {
    required bool isNew,
  }) async =>
      DoctorProfile.fromJson(
        _map(
          await _request(
            isNew ? 'POST' : 'PUT',
            isNew
                ? '/admin/doctors'
                : '/admin/doctors/${Uri.encodeComponent(doctor.id)}',
            body: doctor.toWriteJson(),
          ),
        ),
      );

  Future<void> uploadDoctorImage(String doctorId, XFile file) async {
    await _upload(
      '/admin/doctors/${Uri.encodeComponent(doctorId)}/photo',
      file,
    );
  }

  Future<void> uploadVerificationDocument(String doctorId, XFile file) async {
    await _upload(
      '/admin/doctors/${Uri.encodeComponent(doctorId)}/verification-documents',
      file,
    );
  }

  Future<void> _upload(String path, XFile file) async {
    try {
      final request = http.MultipartRequest('POST', _uri(path))
        ..headers.addAll(await _headers(authenticated: true))
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            await file.readAsBytes(),
            filename: file.name,
            contentType: MediaType.parse(_contentType(file)),
          ),
        );
      final response = await _client.send(request).timeout(
            const Duration(seconds: 60),
          );
      final materialized = await http.Response.fromStream(response);
      if (materialized.statusCode < 200 || materialized.statusCode >= 300) {
        throw DoctorApiException(
          _errorMessage(materialized),
          statusCode: materialized.statusCode,
        );
      }
    } on DoctorApiException {
      rethrow;
    } on TimeoutException {
      throw const DoctorApiException(
        'The upload took too long. Check your connection and retry.',
        statusCode: 408,
      );
    } on Exception {
      throw const DoctorApiException(
        'The upload failed. Check your connection and retry.',
      );
    }
  }

  String _contentType(XFile file) {
    final type = file.mimeType;
    if (type != null &&
        const {'image/jpeg', 'image/png', 'image/webp'}.contains(type)) {
      return type;
    }
    return switch (file.name.split('.').last.toLowerCase()) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
  }

  Future<Uint8List> getVerificationDocument({
    required String doctorId,
    required String documentId,
  }) async {
    final uri = _uri(
      '/admin/doctors/${Uri.encodeComponent(doctorId)}/verification-documents/'
      '${Uri.encodeComponent(documentId)}',
    );
    try {
      final response = await _client
          .get(uri, headers: await _headers(authenticated: true))
          .timeout(const Duration(seconds: 45));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw DoctorApiException(
          _errorMessage(response),
          statusCode: response.statusCode,
        );
      }
      return response.bodyBytes;
    } on DoctorApiException {
      rethrow;
    } on TimeoutException {
      throw const DoctorApiException(
        'The document request timed out. Please retry.',
        statusCode: 408,
      );
    } on Exception {
      throw const DoctorApiException(
        'Could not load the verification document.',
      );
    }
  }

  Future<void> setVerification(
    String doctorId, {
    required String status,
    String? notes,
  }) async {
    await _request(
      'PUT',
      '/admin/doctors/${Uri.encodeComponent(doctorId)}/verification',
      body: {'status': status, 'notes': notes},
    );
  }

  Future<List<DoctorAppointment>> listAdminAppointments() async {
    final data = _list(await _request('GET', '/admin/appointments'));
    return [
      for (final item in data)
        DoctorAppointment.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
  }

  Future<void> moderateAppointment(String id, String status) async {
    await _request(
      'PATCH',
      '/admin/appointments/${Uri.encodeComponent(id)}',
      body: {'status': status},
    );
  }

  Future<List<DoctorReview>> listAdminReviews() async {
    final data = _list(await _request('GET', '/admin/reviews'));
    return [
      for (final item in data)
        DoctorReview.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
  }

  Future<void> moderateReview(String id, String status) async {
    await _request(
      'PATCH',
      '/admin/reviews/${Uri.encodeComponent(id)}',
      body: {'status': status},
    );
  }

  Future<List<DoctorAdminReport>> listAdminReports() async {
    final data = _list(await _request('GET', '/admin/reports'));
    return [
      for (final item in data)
        DoctorAdminReport.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
  }

  Future<void> moderateReport(String id, String status) async {
    await _request(
      'PATCH',
      '/admin/reports/${Uri.encodeComponent(id)}',
      body: {'status': status},
    );
  }

  static String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
