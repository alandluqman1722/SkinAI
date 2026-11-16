class DoctorClinic {
  const DoctorClinic({
    required this.id,
    required this.name,
    required this.city,
    required this.address,
    required this.weeklySchedule,
    this.latitude,
    this.longitude,
    this.phone,
    this.website,
  });

  final String id;
  final String name;
  final String city;
  final String address;
  final List<DoctorAvailabilityRule> weeklySchedule;
  final double? latitude;
  final double? longitude;
  final String? phone;
  final String? website;

  factory DoctorClinic.fromJson(Map<String, dynamic> json) => DoctorClinic(
        id: json['clinic_id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        city: json['city'] as String? ?? '',
        address: json['address'] as String? ?? '',
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        phone: json['phone'] as String?,
        website: json['website'] as String?,
        weeklySchedule: [
          for (final item in json['weekly_schedule'] as List? ?? const [])
            DoctorAvailabilityRule.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
        ],
      );

  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'clinic_id': id,
        'name': name,
        'city': city,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'phone': phone,
        'website': website,
        'weekly_schedule': [
          for (final rule in weeklySchedule) rule.toJson(),
        ],
      };
}

class DoctorAvailabilityRule {
  const DoctorAvailabilityRule({
    required this.weekday,
    required this.times,
  });

  final int weekday;
  final List<String> times;

  factory DoctorAvailabilityRule.fromJson(Map<String, dynamic> json) =>
      DoctorAvailabilityRule(
        weekday: (json['weekday'] as num?)?.toInt() ?? 0,
        times: [
          for (final item in json['times'] as List? ?? const [])
            if (item is String) item,
        ],
      );

  Map<String, dynamic> toJson() => {'weekday': weekday, 'times': times};
}

class DoctorProfile {
  const DoctorProfile({
    required this.id,
    required this.fullName,
    required this.specializations,
    required this.clinics,
    required this.verified,
    required this.publicationStatus,
    this.qualifications = const [],
    this.languages = const [],
    this.experienceYears,
    this.biography = '',
    this.averageRating,
    this.reviewCount = 0,
    this.photoUrl,
    this.verificationStatus = 'unverified',
    this.verificationDocuments = const [],
  });

  final String id;
  final String fullName;
  final List<String> specializations;
  final List<DoctorClinic> clinics;
  final bool verified;
  final String publicationStatus;
  final List<String> qualifications;
  final List<String> languages;
  final int? experienceYears;
  final String biography;
  final double? averageRating;
  final int reviewCount;
  final String? photoUrl;
  final String verificationStatus;
  final List<DoctorVerificationDocument> verificationDocuments;

  factory DoctorProfile.fromJson(Map<String, dynamic> json) => DoctorProfile(
        id: json['id'] as String? ?? '',
        fullName: json['full_name'] as String? ?? '',
        specializations: _stringList(json['specializations']),
        clinics: [
          for (final item in json['clinics'] as List? ?? const [])
            DoctorClinic.fromJson(Map<String, dynamic>.from(item as Map)),
        ],
        verified: json['verified'] == true,
        publicationStatus: json['publication_status'] as String? ?? 'draft',
        qualifications: _stringList(json['qualifications']),
        languages: _stringList(json['languages']),
        experienceYears: (json['experience_years'] as num?)?.toInt(),
        biography: json['biography'] as String? ?? '',
        averageRating: (json['average_rating'] as num?)?.toDouble(),
        reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
        photoUrl: json['photo_url'] as String?,
        verificationStatus:
            json['verification_status'] as String? ?? 'unverified',
        verificationDocuments: [
          for (final item in json['verification_documents'] as List? ?? const [])
            DoctorVerificationDocument.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
        ],
      );

  Map<String, dynamic> toWriteJson() => {
        'full_name': fullName,
        'qualifications': qualifications,
        'specializations': specializations,
        'experience_years': experienceYears,
        'biography': biography,
        'languages': languages,
        'clinics': [for (final clinic in clinics) clinic.toJson()],
        'publication_status': publicationStatus,
      };

  static List<String> _stringList(Object? value) => [
        for (final item in value as List? ?? const [])
          if (item is String) item,
      ];
}

class DoctorVerificationDocument {
  const DoctorVerificationDocument({
    required this.id,
    required this.filename,
    required this.contentType,
    required this.uploadedAt,
  });

  final String id;
  final String filename;
  final String contentType;
  final String uploadedAt;

  factory DoctorVerificationDocument.fromJson(Map<String, dynamic> json) =>
      DoctorVerificationDocument(
        id: json['id'] as String? ?? '',
        filename: json['filename'] as String? ?? '',
        contentType: json['content_type'] as String? ?? '',
        uploadedAt: json['uploaded_at'] as String? ?? '',
      );
}

class DoctorReview {
  const DoctorReview({
    required this.id,
    required this.rating,
    required this.comment,
    required this.createdAt,
    this.reportCount = 0,
  });

  final String id;
  final int rating;
  final String comment;
  final String createdAt;
  final int reportCount;

  factory DoctorReview.fromJson(Map<String, dynamic> json) => DoctorReview(
        id: json['id'] as String? ?? '',
        rating: (json['rating'] as num?)?.toInt() ?? 0,
        comment: json['comment'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
        reportCount: (json['report_count'] as num?)?.toInt() ?? 0,
      );
}

class DoctorAppointment {
  const DoctorAppointment({
    required this.id,
    required this.doctorId,
    required this.doctorName,
    required this.clinicId,
    required this.clinicName,
    required this.city,
    required this.date,
    required this.time,
    required this.status,
    this.patientName,
  });

  final String id;
  final String doctorId;
  final String doctorName;
  final String clinicId;
  final String clinicName;
  final String city;
  final String date;
  final String time;
  final String status;
  final String? patientName;

  factory DoctorAppointment.fromJson(Map<String, dynamic> json) =>
      DoctorAppointment(
        id: json['id'] as String? ?? '',
        doctorId: json['doctor_id'] as String? ?? '',
        doctorName: json['doctor_name'] as String? ?? '',
        clinicId: json['clinic_id'] as String? ?? '',
        clinicName: json['clinic_name'] as String? ?? '',
        city: json['city'] as String? ?? '',
        date: json['appointment_date'] as String? ?? '',
        time: json['appointment_time'] as String? ?? '',
        status: json['status'] as String? ?? 'pending',
        patientName: json['patient_name'] as String?,
      );
}

class DoctorAdminReport {
  const DoctorAdminReport({
    required this.id,
    required this.doctorId,
    required this.reviewId,
    required this.reason,
    required this.status,
  });

  final String id;
  final String doctorId;
  final String reviewId;
  final String reason;
  final String status;

  factory DoctorAdminReport.fromJson(Map<String, dynamic> json) =>
      DoctorAdminReport(
        id: json['id'] as String? ?? '',
        doctorId: json['doctor_id'] as String? ?? '',
        reviewId: json['review_id'] as String? ?? '',
        reason: json['reason'] as String? ?? '',
        status: json['status'] as String? ?? 'pending',
      );
}
