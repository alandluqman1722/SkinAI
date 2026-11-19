import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'admin_models.dart';

typedef AdminIdTokenProvider = Future<String?> Function();

class AdminApiException implements Exception {
  const AdminApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class AdminApiService {
  AdminApiService({
    required String baseUrl,
    required AdminIdTokenProvider idTokenProvider,
    http.Client? client,
  })  : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _idTokenProvider = idTokenProvider,
        _client = client ?? http.Client();

  final String _baseUrl;
  final AdminIdTokenProvider _idTokenProvider;
  final http.Client _client;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$_baseUrl/api/admin$path').replace(queryParameters: query);

  Future<Map<String, String>> _headers() async {
    final token = await _idTokenProvider();
    if (token == null || token.isEmpty) {
      throw const AdminApiException(
        'Sign in to verify administrator access.',
        statusCode: 401,
      );
    }
    return {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    try {
      final headers = await _headers();
      http.Response response;
      final uri = _uri(path, query);
      switch (method) {
        case 'GET':
          response = await _client.get(uri, headers: headers).timeout(
                const Duration(seconds: 45),
              );
          break;
        case 'POST':
          headers['Content-Type'] = 'application/json';
          response = await _client
              .post(uri, headers: headers, body: jsonEncode(body))
              .timeout(const Duration(seconds: 45));
          break;
        case 'PATCH':
          headers['Content-Type'] = 'application/json';
          response = await _client
              .patch(uri, headers: headers, body: jsonEncode(body))
              .timeout(const Duration(seconds: 45));
          break;
        default:
          throw ArgumentError.value(method, 'method');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AdminApiException(
          _errorMessage(response),
          statusCode: response.statusCode,
        );
      }
      try {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        throw const AdminApiException(
          'The admin service returned an invalid response.',
        );
      }
    } on AdminApiException {
      rethrow;
    } on TimeoutException {
      throw const AdminApiException(
        'The request took too long. Check your connection and retry.',
        statusCode: 408,
      );
    } on Exception {
      throw const AdminApiException(
        'Could not connect to the admin service. Check your connection and retry.',
      );
    }
  }

  Future<dynamic> _get(String path, {Map<String, String>? query}) =>
      _request('GET', path, query: query);

  String _errorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(
        response.bodyBytes.isEmpty ? '{}' : utf8.decode(response.bodyBytes),
      );
      if (decoded is Map<String, dynamic> &&
          decoded['detail'] is String &&
          (decoded['detail'] as String).isNotEmpty) {
        return decoded['detail'] as String;
      }
    } on FormatException {
      return 'Admin request failed (${response.statusCode}).';
    }
    return 'Admin request failed (${response.statusCode}).';
  }

  Future<bool> checkAdminStatus() async {
    final response = await _get('/status');
    if (response is! Map<String, dynamic> || response['admin'] is! bool) {
      throw const AdminApiException(
        'The admin service returned an invalid access response.',
      );
    }
    return response['admin'] as bool;
  }

  Future<AdminDashboardSummary> loadDashboard({int days = 7}) async {
    if (days != 7 && days != 30) {
      throw ArgumentError.value(days, 'days', 'Expected 7 or 30.');
    }
    final response = await _get(
      '/dashboard',
      query: {'days': '$days'},
    );
    try {
      return AdminDashboardSummary.fromJson(response);
    } on FormatException catch (error) {
      throw AdminApiException(error.message);
    }
  }

  Future<AdminUsersPage> loadUsers({
    String search = '',
    int pageSize = 50,
    String? cursor,
    bool? blocked,
    bool? disabled,
  }) async {
    final query = <String, String>{
      'search': search,
      'page_size': '$pageSize',
      if (cursor != null) 'cursor': cursor,
      if (blocked != null) 'blocked': '$blocked',
      if (disabled != null) 'disabled': '$disabled',
    };
    try {
      return AdminUsersPage.fromJson(await _get('/users', query: query));
    } on FormatException catch (error) {
      throw AdminApiException(error.message);
    }
  }

  Future<AdminUserUsage> loadUserUsage(String uid) async {
    try {
      return AdminUserUsage.fromJson(await _get('/users/$uid/usage'));
    } on FormatException catch (error) {
      throw AdminApiException(error.message);
    }
  }

  Future<AdminAppointmentsPage> loadAppointments({
    String? status,
    String? doctorId,
    String? dateFrom,
    String? dateTo,
    int pageSize = 50,
    String? cursor,
  }) async {
    final query = <String, String>{
      'page_size': '$pageSize',
      if (status != null) 'status': status,
      if (doctorId != null && doctorId.isNotEmpty) 'doctor_id': doctorId,
      if (dateFrom != null) 'date_from': dateFrom,
      if (dateTo != null) 'date_to': dateTo,
      if (cursor != null) 'cursor': cursor,
    };
    try {
      return AdminAppointmentsPage.fromJson(
        await _get('/appointments', query: query),
      );
    } on FormatException catch (error) {
      throw AdminApiException(error.message);
    }
  }

  Future<void> moderateAppointment(
    String id, {
    required String status,
    required String reason,
  }) async {
    await _request(
      'PATCH',
      '/appointments/${Uri.encodeComponent(id)}',
      body: {'status': status, 'reason': reason},
    );
  }

  Future<void> setUserBlocked(String uid, bool blocked) async {
    await _request(
      'PATCH',
      '/users/$uid/block',
      body: {'blocked': blocked},
    );
  }

  Future<void> setUserDisabled(String uid, bool disabled) async {
    await _request(
      'PATCH',
      '/users/$uid/disabled',
      body: {'disabled': disabled},
    );
  }

  Future<void> requestPasswordReset(String uid) async {
    await _request('POST', '/users/$uid/password-reset');
  }

  Future<void> requestUserDataDeletion(String uid) async {
    await _request(
      'POST',
      '/users/$uid/deletion-requests',
      body: {'confirmation': true},
    );
  }
}
