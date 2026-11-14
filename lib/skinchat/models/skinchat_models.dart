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
  });

  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? uploadedImageId;
  final DateTime? imageUploadTimestamp;
  final String? initialAnalysis;
  final String detectedLanguage;
  final bool imageAvailable;

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
    );
  }

  SkinChatConversation copyWith({
    String? uploadedImageId,
    DateTime? imageUploadTimestamp,
    String? initialAnalysis,
    String? detectedLanguage,
    DateTime? updatedAt,
    bool? imageAvailable,
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
