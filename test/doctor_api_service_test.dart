import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skin_ai/doctors/doctor_api_service.dart';

http.Response _json(Object value, {int statusCode = 200}) => http.Response(
      jsonEncode(value),
      statusCode,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _doctorJson() => {
      'id': 'doctor-1',
      'full_name': 'Doctor profile entered by admin',
      'verified': true,
      'publication_status': 'published',
      'verification_status': 'approved',
      'specializations': ['Dermatology'],
      'qualifications': ['Verified qualification'],
      'experience_years': 8,
      'clinics': [
        {
          'clinic_id': 'clinic-1',
          'name': 'Verified clinic',
          'city': 'Erbil',
          'address': 'Verified address',
          'weekly_schedule': [
            {
              'weekday': 0,
              'times': ['09:00']
            },
          ],
        },
      ],
      'average_rating': 4.5,
      'review_count': 2,
      'photo_url': '/api/doctors/doctor-1/photo',
    };

void main() {
  test('directory sends filters and parses only returned doctor records',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/doctors');
      expect(request.url.queryParameters, {
        'search': 'Doctor',
        'city': 'Erbil',
        'specialization': 'Dermatology',
        'clinic': 'Verified clinic',
        'available_within_days': '7',
        'sort': 'experience',
      });
      return _json([_doctorJson()]);
    });
    final api = DoctorApiService(
      baseUrl: 'http://localhost:8000/',
      idTokenProvider: () async => null,
      client: client,
    );

    final doctors = await api.listDoctors(
      search: 'Doctor',
      city: 'Erbil',
      specialization: 'Dermatology',
      clinic: 'Verified clinic',
      availableWithinDays: 7,
      sort: 'experience',
    );

    expect(doctors, hasLength(1));
    expect(doctors.single.verified, isTrue);
    expect(
        doctors.single.clinics.single.weeklySchedule.single.times, ['09:00']);
    expect(doctors.single.photoUrl, '/api/doctors/doctor-1/photo');
    client.close();
  });

  test('favorite toggles use the authenticated account endpoints', () async {
    final methods = <String>[];
    final client = MockClient((request) async {
      methods.add('${request.method} ${request.url.path}');
      return _json({'is_favorite': request.method == 'PUT'});
    });
    final api = DoctorApiService(
      baseUrl: 'http://localhost:8000',
      idTokenProvider: () async => 'firebase-id-token',
      client: client,
    );

    expect(await api.setFavorite('doctor/1', true), isTrue);
    expect(await api.setFavorite('doctor/1', false), isFalse);
    expect(methods, [
      'PUT /api/doctors/doctor%2F1/favorite',
      'DELETE /api/doctors/doctor%2F1/favorite',
    ]);
    client.close();
  });

  test('booking submits the selected slot and returns its real status',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/doctors/appointments');
      expect(jsonDecode(request.body), {
        'doctor_id': 'doctor-1',
        'clinic_id': 'clinic-1',
        'appointment_date': '2030-04-05',
        'appointment_time': '09:00',
      });
      return _json({
        'id': 'appointment-1',
        'doctor_id': 'doctor-1',
        'doctor_name': 'Doctor profile entered by admin',
        'clinic_id': 'clinic-1',
        'clinic_name': 'Verified clinic',
        'city': 'Erbil',
        'appointment_date': '2030-04-05',
        'appointment_time': '09:00',
        'status': 'pending',
      });
    });
    final api = DoctorApiService(
      baseUrl: 'http://localhost:8000',
      idTokenProvider: () async => 'firebase-id-token',
      client: client,
    );

    final appointment = await api.bookAppointment(
      doctorId: 'doctor-1',
      clinicId: 'clinic-1',
      date: DateTime(2030, 4, 5),
      time: '09:00',
    );

    expect(appointment.id, 'appointment-1');
    expect(appointment.status, 'pending');
    client.close();
  });

  test('review requires an authenticated token before making a request',
      () async {
    var called = false;
    final client = MockClient((_) async {
      called = true;
      return _json({});
    });
    final api = DoctorApiService(
      baseUrl: 'http://localhost:8000',
      idTokenProvider: () async => null,
      client: client,
    );

    await expectLater(
      api.submitReview(
        appointmentId: 'appointment-1',
        rating: 5,
        comment: 'Review after my appointment.',
      ),
      throwsA(isA<DoctorApiException>()),
    );
    expect(called, isFalse);
    client.close();
  });
}
