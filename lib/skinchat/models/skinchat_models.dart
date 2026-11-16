class SkinChatScanContext {
  const SkinChatScanContext({
    required this.scanId,
    required this.detectedCondition,
    required this.confidence,
    required this.scanDate,
    this.summary,
    this.bodyLocation,
    this.hasOriginalImage = false,
  });

  final String scanId;
  final String detectedCondition;
  final double confidence;
  final DateTime scanDate;
  final String? summary;
  final String? bodyLocation;
  final bool hasOriginalImage;

  Map<String, Object?> toJson() => {
        'scan_id': scanId,
        'detected_condition': detectedCondition,
        'confidence': confidence,
        'scan_date': scanDate.toUtc().toIso8601String(),
        if (summary != null) 'summary': summary,
        if (bodyLocation != null) 'body_location': bodyLocation,
        'has_original_image': hasOriginalImage,
      };

  factory SkinChatScanContext.fromJson(Map<String, dynamic> json) {
    final scanId = json['scan_id'];
    final condition = json['detected_condition'];
    final confidence = json['confidence'];
    final scanDate = DateTime.tryParse(json['scan_date']?.toString() ?? '');
    final summary = json['summary'];
    final bodyLocation = json['body_location'];
    final hasOriginalImage = json['has_original_image'];
    if (scanId is! String ||
        scanId.isEmpty ||
        condition is! String ||
        condition.isEmpty ||
        confidence is! num ||
        !confidence.isFinite ||
        confidence < 0 ||
        confidence > 100 ||
        scanDate == null ||
        (summary != null && summary is! String) ||
        (bodyLocation != null && bodyLocation is! String) ||
        (hasOriginalImage != null && hasOriginalImage is! bool)) {
      throw const FormatException('Invalid SkinChat scan context.');
    }

    return SkinChatScanContext(
      scanId: scanId,
      detectedCondition: condition,
      confidence: confidence.toDouble(),
      scanDate: scanDate,
      summary: summary as String?,
      bodyLocation: bodyLocation as String?,
      hasOriginalImage: hasOriginalImage == true,
    );
  }
}

class SkinChatConversation {
  const SkinChatConversation({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.uploadedImageId,
    this.imageUploadTimestamp,
    this.initialAnalysis,
    this.detectedLanguage = 'en',
    this.imageAvailable = true,
    this.scanContext,
  });

  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? uploadedImageId;
  final DateTime? imageUploadTimestamp;
  final String? initialAnalysis;
  final String detectedLanguage;
  final bool imageAvailable;
  final SkinChatScanContext? scanContext;

  bool get hasImage => uploadedImageId != null && imageAvailable;
  bool get hasImageReference => uploadedImageId != null;

  factory SkinChatConversation.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(Object? value) =>
        DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();

    return SkinChatConversation(
      id: json['conversation_id'] as String,
      createdAt: parseDate(json['created_at']),
      updatedAt: parseDate(json['updated_at']),
      uploadedImageId: json['uploaded_image_id'] as String?,
      imageUploadTimestamp: json['image_upload_timestamp'] == null
          ? null
          : parseDate(json['image_upload_timestamp']),
      initialAnalysis: json['initial_analysis'] as String?,
      detectedLanguage: json['detected_language'] as String? ?? 'en',
      imageAvailable: json['image_available'] as bool? ??
          (json['uploaded_image_id'] != null),
      scanContext: json['scan_context'] == null
          ? null
          : SkinChatScanContext.fromJson(
              Map<String, dynamic>.from(json['scan_context'] as Map),
            ),
    );
  }

  SkinChatConversation copyWith({
    String? uploadedImageId,
    DateTime? imageUploadTimestamp,
    String? initialAnalysis,
    String? detectedLanguage,
    DateTime? updatedAt,
    bool? imageAvailable,
    SkinChatScanContext? scanContext,
  }) =>
      SkinChatConversation(
        id: id,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        uploadedImageId: uploadedImageId ?? this.uploadedImageId,
        imageUploadTimestamp: imageUploadTimestamp ?? this.imageUploadTimestamp,
        initialAnalysis: initialAnalysis ?? this.initialAnalysis,
        detectedLanguage: detectedLanguage ?? this.detectedLanguage,
        imageAvailable: imageAvailable ?? this.imageAvailable,
        scanContext: scanContext ?? this.scanContext,
      );
}

class SkinChatMessage {
  const SkinChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.language,
    required this.createdAt,
  });

  final String id;
  final String role;
  final String content;
  final String language;
  final DateTime createdAt;

  factory SkinChatMessage.fromJson(Map<String, dynamic> json) =>
      SkinChatMessage(
        id: json['message_id'] as String,
        role: json['role'] as String,
        content: json['content'] as String,
        language: json['language'] as String? ?? 'en',
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}

class SkinChatMessagesPage {
  const SkinChatMessagesPage({
    required this.messages,
    this.nextBefore,
  });

  final List<SkinChatMessage> messages;
  final String? nextBefore;

  factory SkinChatMessagesPage.fromJson(Map<String, dynamic> json) =>
      SkinChatMessagesPage(
        messages: (json['messages'] as List<dynamic>)
            .map(
              (message) => SkinChatMessage.fromJson(
                message as Map<String, dynamic>,
              ),
            )
            .toList(),
        nextBefore: json['next_before'] as String?,
      );
}
