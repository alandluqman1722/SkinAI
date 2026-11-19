import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:skin_ai/design/app_components.dart';
import 'package:skin_ai/design/app_design_system.dart';
import 'package:skin_ai/image_picker_feedback.dart';
import 'package:skin_ai/localization/app_localizations.dart';
import 'package:skin_ai/medical_scan_api.dart';
import 'package:skin_ai/skinchat/models/skinchat_models.dart';
import 'package:skin_ai/skinchat/services/skinchat_api_service.dart';

const Map<String, Map<String, String>> _copy = {
  'en': {
    'title': 'SkinChat AI',
    'subtitle': 'Skincare education, tailored to your questions',
    'new': 'New conversation',
    'history': 'Conversation history',
    'upload': 'Upload a skin image',
    'uploadHint': 'Images are stored privately and are never analyzed by AI.',
    'image': 'Image context',
    'analysis': 'Initial image analysis',
    'notAnalyzed': 'Images are stored privately and are not analyzed by SkinChat.',
    'remove': 'Delete conversation',
    'cancel': 'Cancel',
    'delete': 'Delete',
    'deleteMessage': 'Delete message',
    'deleteConfirm': 'Delete this conversation and its stored image?',
    'deleteMessageConfirm': 'Delete this message and its paired reply?',
    'emptyHistory': 'No conversations yet.',
    'emptyChat': 'Your conversation will appear here.',
    'generalMode':
        'General skincare answers are unavailable right now. Saved conversation history remains available.',
    'scanAttached': 'Attached scan (screening result)',
    'scanId': 'Scan ID',
    'condition': 'Possible pattern',
    'confidence': 'Model confidence',
    'scanDate': 'Scan date',
    'bodyLocation': 'Body area',
    'screeningDisclaimer':
        'This is an AI screening prediction, not a diagnosis.',
    'scanImageUnavailable': 'The original scan image is not available.',
    'placeholder': 'Ask a skincare question…',
    'send': 'Send message',
    'sending': 'SkinChat is responding…',
    'older': 'Load older messages',
    'retry': 'Try again',
    'sendFailed':
        'Could not send this message. Check your connection and retry.',
    'requestTimeout':
        'The reply is taking longer than expected. Retry to check for a saved reply.',
    'disclaimer':
        'Educational information only—not a diagnosis or substitute for a dermatologist.',
    'suggest1': 'How can I care for oily skin?',
    'suggest2': 'What ingredients help keep skin hydrated?',
    'suggest3': 'How do I choose a sunscreen?',
    'uploading': 'Uploading image securely…',
    'uploaded': 'Image saved securely',
    'imageUnavailable':
        'The stored image is unavailable. Text chat can continue; start a new conversation to upload another.',
    'loadFailed': 'Could not load this conversation. Please retry.',
    'imagePickerFailed': 'Could not open the image picker. Please retry.',
  },
  'ku': {
    'title': 'SkinChat AI',
    'subtitle': 'زانیاریی چاودێری پێست بەپێی پرسیارەکانت',
    'new': 'گفتوگۆی نوێ',
    'history': 'مێژووی گفتوگۆ',
    'upload': 'وێنەیەکی پێست باربکە',
    'uploadHint':
        'وێنەکان بە تایبەتی هەڵدەگیرێن و بە زیرەکی دەستکرد شیکاری ناکرێن.',
    'image': 'وێنەی گفتوگۆ',
    'analysis': 'شیکردنەوەی سەرەتایی',
    'notAnalyzed': 'وێنەکان بە تایبەتی هەڵدەگیرێن و لە SkinChat شیکار ناکرێن.',
    'remove': 'سڕینەوەی گفتوگۆ',
    'cancel': 'پاشگەزبوونەوە',
    'delete': 'بسڕەوە',
    'deleteMessage': 'سڕینەوەی نامە',
    'deleteConfirm': 'ئەم گفتوگۆیە و وێنە هەڵگیراوەکەی بسڕێتەوە؟',
    'deleteMessageConfirm': 'ئەم نامەیە و وەڵامەکەی بسڕێتەوە؟',
    'emptyHistory': 'هێشتا هیچ گفتوگۆیەک نییە.',
    'emptyChat': 'گفتوگۆکەت لێرە دەردەکەوێت.',
    'generalMode':
        'وەڵامی گشتیی چاودێری پێست ئێستا بەردەست نییە. مێژووی گفتوگۆی پاشەکەوتکراو بەردەستە.',
    'scanAttached': 'سکانی پەیوەستکراو (ئەنجامی پشکنین)',
    'scanId': 'ژمارەی سکان',
    'condition': 'شێوازی ئەگەری',
    'confidence': 'متمانەی مۆدێل',
    'scanDate': 'بەرواری سکان',
    'bodyLocation': 'شوێنی لەش',
    'screeningDisclaimer': 'ئەمە پێشبینیی پشکنینی AI ـە، نەک تشخیص.',
    'scanImageUnavailable': 'وێنەی ڕەسەنی سکان بەردەست نییە.',
    'placeholder': 'پرسیارێکی لەبارەی چاودێری پێست بکە…',
    'send': 'ناردنی پرسیار',
    'sending': 'SkinChat وەڵام دەداتەوە…',
    'older': 'بارکردنی نامە کۆنەکان',
    'retry': 'دووبارە هەوڵبدەوە',
    'requestTimeout':
        'وەڵامەکە زیاتر لە چاوەڕوانکراو دەخایەنێت. دووبارە هەوڵبدەوە بۆ پشکنینی وەڵامێکی پاشەکەوتکراو.',
    'disclaimer': 'تەنها زانیاریی گشتییە؛ نە تشخیصە و نە جێگرەوەی پزیشکی پێست.',
    'suggest1': 'چۆن چاودێری پێستی چەور بکەم؟',
    'suggest2': 'کام پێکهاتە ئاوی پێست دەپارێزێت؟',
    'suggest3': 'چۆن کرێمی خۆر هەڵبژێرم؟',
    'uploading': 'وێنە بە شێوەیەکی پارێزراو بار دەکرێت…',
    'uploaded': 'وێنە بە پارێزراوی هەڵگیرا',
    'imageUnavailable':
        'وێنەی هەڵگیراو بەردەست نییە. دەتوانیت بە چات بەردەوام بیت یان گفتوگۆیەکی نوێ دەستپێبکەیت.',
    'loadFailed':
        'بارکردنی ئەم گفتوگۆیە سەرکەوتوو نەبوو. تکایە دووبارە هەوڵبدەوە.',
    'imagePickerFailed':
        'کردنەوەی هەڵبژێری وێنە سەرکەوتوو نەبوو. تکایە دووبارە هەوڵبدەوە.',
  },
  'bad': {
    'title': 'SkinChat AI',
    'subtitle': 'زانیاریا چاڤدێریا پێستی ب پێی پرسیارێن تە',
    'new': 'گفتوگۆیەکا نوی',
    'history': 'مێژوویا گفتوگۆیان',
    'upload': 'وێنەیەکا پێستێ بارکە',
    'uploadHint':
        'وێنە ب تایبەتی دهێنە هەڵگرتن و ب هووشێ دەستکرد ناهێنە شیکرن.',
    'image': 'وێنەیا گفتوگۆیێ',
    'analysis': 'شیکرنا دەستپێکێ',
    'notAnalyzed': 'وێنە ب تایبەتی دهێنە هەڵگرتن و ل SkinChat شیکار ناکرێن.',
    'remove': 'گفتوگۆیێ ژێببە',
    'cancel': 'بتال بکە',
    'delete': 'ژێببە',
    'deleteMessage': 'نامەیێ ژێببە',
    'deleteConfirm': 'ئەرێ ئەڤ گفتوگۆ و وێنەیا هەڵگیرا ژێببەم؟',
    'deleteMessageConfirm': 'ئەرێ ئەڤ نامە و بەرسڤا وێ ژێببەم؟',
    'emptyHistory': 'هێشتا چ گفتوگۆ نینە.',
    'emptyChat': 'گفتوگۆیا تە ل ڤێرێ دیار دبیت.',
    'generalMode':
        'بەرسڤێن گشتی یێن چاڤدێریا پێستی نوکە بەردەست نینن. مێژوویا گفتوگۆیێن پاراستی بەردەستە.',
    'scanAttached': 'سکانێ پەیوەستکری (ئەنجامێ پشکنینێ)',
    'scanId': 'ژمارا سکانێ',
    'condition': 'شێوازا ئەگەری',
    'confidence': 'باوەریا مۆدێلێ',
    'scanDate': 'بەروارێ سکانێ',
    'bodyLocation': 'شوێنێ لەشی',
    'screeningDisclaimer': 'ئەڤە پێشبینیا پشکنینا AI یە، نە تشخیص.',
    'scanImageUnavailable': 'وێنەیا ڕەسەنی یا سکانێ بەردەست نینە.',
    'placeholder': 'پرسیارەکا دەر بارێ چاڤدێریا پێستی بکە…',
    'send': 'پرسیارێ بفرێکە',
    'sending': 'SkinChat بەرسڤ ددەت…',
    'older': 'نامەیێن کەڤن بارکە',
    'retry': 'دووبارە هەول بدە',
    'sendFailed':
        'ناردنی ئەم نامەیە سەرکەوتوو نەبوو. پەیوەندی ئینتەرنێت بپشکنە و دووبارە هەوڵ بدە.',
    'requestTimeout':
        'بەرسڤ د دیرکەفتییە. ژ نوو هەول بدە بۆ پشکنینا بەرسڤەکا هاتیە پاشەکەفتکرن.',
    'disclaimer': 'تەنێ زانیاریا گشتییە؛ نە تشخیصە و نە جێگرەوەیا دکتۆرێ پێست.',
    'suggest1': 'چوا چاڤدێریا پێستا چەوری بکەم؟',
    'suggest2': 'کام پێکهاتە ئاڤا پێستی دپارێزیت؟',
    'suggest3': 'چوا پارێزەرێ خۆر هەلبژێرم؟',
    'uploading': 'وێنە ب شێوەیەکێ پاراستی دهێتە بارکرن…',
    'uploaded': 'وێنە ب پاراستی هاتە هەڵگرتن',
    'imageUnavailable':
        'وێنەیا هەڵگیرا بەردەست نینە. دکارێ ب چاتێ بەردەوام بیت یان گفتوگۆیەکا نوی دەستپێبکەی.',
    'loadFailed': 'بارکرنا ئەڤ گفتوگۆیێ سەرکەفتی نەبوو. ژ نوو هەول بدە.',
    'imagePickerFailed':
        'ڤەکرنا هەلبژێرێ وێنەیێ سەرکەفتی نەبوو. ژ نوو هەول بدە.',
  },
  'ar': {
    'title': 'SkinChat AI',
    'subtitle': 'تثقيف حول العناية بالبشرة وفق أسئلتك',
    'new': 'محادثة جديدة',
    'history': 'سجل المحادثات',
    'upload': 'ارفع صورة للبشرة',
    'uploadHint':
        'تُحفظ الصور بخصوصية ولا يرسلها التطبيق إلى الذكاء الاصطناعي.',
    'image': 'سياق الصورة',
    'analysis': 'التحليل الأولي للصورة',
    'notAnalyzed': 'تُحفظ الصور بخصوصية ولا يحللها SkinChat.',
    'remove': 'حذف المحادثة',
    'cancel': 'إلغاء',
    'delete': 'حذف',
    'deleteMessage': 'حذف الرسالة',
    'deleteConfirm': 'هل تريد حذف هذه المحادثة والصورة المخزنة؟',
    'deleteMessageConfirm': 'هل تريد حذف هذه الرسالة والرد المرتبط بها؟',
    'emptyHistory': 'لا توجد محادثات بعد.',
    'emptyChat': 'ستظهر محادثتك هنا.',
    'generalMode':
        'إجابات العناية العامة بالبشرة غير متاحة حاليًا. يظل سجل المحادثة المحفوظ متاحًا.',
    'scanAttached': 'الفحص المرفق (نتيجة أولية)',
    'scanId': 'معرّف الفحص',
    'condition': 'نمط محتمل',
    'confidence': 'ثقة النموذج',
    'scanDate': 'تاريخ الفحص',
    'bodyLocation': 'منطقة الجسم',
    'screeningDisclaimer': 'هذا تنبؤ فحص بالذكاء الاصطناعي، وليس تشخيصًا.',
    'scanImageUnavailable': 'الصورة الأصلية للفحص غير متاحة.',
    'placeholder': 'اسأل عن العناية بالبشرة…',
    'send': 'إرسال الرسالة',
    'sending': 'SkinChat يكتب…',
    'older': 'تحميل الرسائل الأقدم',
    'retry': 'حاول مرة أخرى',
    'sendFailed': 'تعذّر إرسال هذه الرسالة. تحقق من الاتصال وحاول مجددًا.',
    'requestTimeout':
        'تأخر الرد أكثر من المتوقع. أعد المحاولة للتحقق من وجود رد محفوظ.',
    'disclaimer':
        'معلومات تثقيفية فقط، وليست تشخيصًا أو بديلًا عن طبيب الجلدية.',
    'suggest1': 'كيف أعتني بالبشرة الدهنية؟',
    'suggest2': 'ما المكونات التي تساعد على ترطيب البشرة؟',
    'suggest3': 'كيف أختار واقي الشمس؟',
    'uploading': 'يتم رفع الصورة بشكل آمن…',
    'uploaded': 'تم حفظ الصورة بأمان',
    'imageUnavailable':
        'الصورة المحفوظة لم تعد متاحة. يمكنك متابعة المحادثة النصية أو بدء محادثة جديدة لرفع صورة أخرى.',
    'loadFailed': 'تعذّر تحميل هذه المحادثة. يرجى المحاولة مرة أخرى.',
    'imagePickerFailed': 'تعذّر فتح منتقي الصور. يرجى المحاولة مرة أخرى.',
  },
};

class SkinChatScreen extends StatefulWidget {
  const SkinChatScreen({
    required this.baseUrl,
    required this.languageCode,
    this.api,
    this.scanContext,
    this.scanImageBytes,
    super.key,
  });

  final String baseUrl;
  final String languageCode;
  final SkinChatApiService? api;
  final SkinChatScanContext? scanContext;
  final Uint8List? scanImageBytes;

  @override
  State<SkinChatScreen> createState() => _SkinChatScreenState();
}

class _SkinChatScreenState extends State<SkinChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();
  late final SkinChatApiService _api;
  List<SkinChatConversation> _conversations = [];
  List<SkinChatMessage> _messages = [];
  SkinChatConversation? _conversation;
  Uint8List? _imageBytes;
  Uint8List? _scanImageBytes;
  String? _nextBefore;
  bool _loading = true;
  bool _uploading = false;
  double _uploadProgress = 0;
  bool _sending = false;
  bool _loadingOlder = false;
  bool _messageFailed = false;
  bool _scanCardExpanded = false;
  String? _pendingMessageId;
  String? _pendingMessageContent;

  String get _language =>
      _copy.containsKey(widget.languageCode) ? widget.languageCode : 'en';
  String t(String key) =>
      _copy[_language]![key] ??
      AppLocalizations.forLanguageCode(_language).text(key);

  bool get _rtl => _language != 'en';
  SkinChatScanContext? get _activeScanContext =>
      _conversation == null ? widget.scanContext : _conversation!.scanContext;

  @override
  void initState() {
    super.initState();
    _api = widget.api ??
        SkinChatApiService(
          baseUrl: widget.baseUrl,
          idTokenProvider: () async =>
              await FirebaseAuth.instance.currentUser?.getIdToken(),
        );
    _restoreConversations();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _restoreConversations() async {
    try {
      final conversations = await _api.listConversations();
      if (!mounted) return;
      setState(() {
        _conversations = conversations;
        _loading = false;
      });
      if (widget.scanContext != null) {
        final matchingConversation = conversations
            .where(
              (conversation) =>
                  conversation.scanContext?.scanId ==
                  widget.scanContext!.scanId,
            )
            .firstOrNull;
        if (matchingConversation != null) {
          await _selectConversation(matchingConversation);
        } else {
          await _startConversation();
        }
      } else if (conversations.isNotEmpty) {
        await _selectConversation(conversations.first);
      } else {
        await _startConversation();
      }
    } on SkinChatApiException catch (error) {
      if (mounted) {
        setState(() => _loading = false);
        _showError(error.message);
      }
    } on Exception {
      if (mounted) {
        setState(() => _loading = false);
        _showError(t('loadFailed'));
      }
    }
  }

  Future<void> _refreshConversations() async {
    final conversations = await _api.listConversations();
    if (mounted) setState(() => _conversations = conversations);
  }

  Future<void> _selectConversation(SkinChatConversation conversation) async {
    var selectedConversation = conversation;
    setState(() {
      _loading = true;
      _conversation = conversation;
      _messages = [];
      _imageBytes = null;
      _scanImageBytes = null;
      _nextBefore = null;
      _pendingMessageId = null;
      _pendingMessageContent = null;
      _messageFailed = false;
      _messageController.clear();
    });
    try {
      final page = await _api.getMessages(conversation.id);
      Uint8List? imageBytes;
      Uint8List? scanImageBytes;
      if (conversation.hasImage) {
        try {
          imageBytes = await _api.getImage(conversation.id);
        } on SkinChatApiException catch (error) {
          if (error.statusCode != 404) rethrow;
          selectedConversation = conversation.copyWith(imageAvailable: false);
        }
      }
      final scanContext = conversation.scanContext;
      if (scanContext != null) {
        if (widget.scanContext?.scanId == scanContext.scanId) {
          scanImageBytes = widget.scanImageBytes;
        }
        try {
          scanImageBytes ??= await _loadOriginalScanImage(scanContext);
        } on MedicalScanApiException catch (error) {
          if (mounted && error.statusCode != 404) _showError(error.message);
        } on Exception {
          if (mounted) _showError(t('scanImageUnavailable'));
        }
      }
      if (!mounted) return;
      setState(() {
        _conversation = selectedConversation;
        _conversations = _conversations
            .map(
              (item) => item.id == selectedConversation.id
                  ? selectedConversation
                  : item,
            )
            .toList();
        _messages = page.messages;
        _nextBefore = page.nextBefore;
        _imageBytes = imageBytes;
        _scanImageBytes = scanImageBytes;
        _loading = false;
      });
      _scrollToBottom();
    } on SkinChatApiException catch (error) {
      if (mounted) {
        setState(() => _loading = false);
        _showError(error.message);
      }
    }
  }

  Future<void> _startConversation() async {
    try {
      final conversation = await _api.createConversation(
        scanContext: widget.scanContext,
      );
      if (!mounted) return;
      setState(() {
        _conversations = [conversation, ..._conversations];
        _conversation = conversation;
        _messages = [];
        _imageBytes = null;
        _scanImageBytes = widget.scanImageBytes;
        _nextBefore = null;
        _pendingMessageId = null;
        _pendingMessageContent = null;
        _messageFailed = false;
        _messageController.clear();
      });
      final scanContext = conversation.scanContext;
      if (scanContext != null && _scanImageBytes == null) {
        try {
          final image = await _loadOriginalScanImage(scanContext);
          if (mounted && _conversation?.id == conversation.id) {
            setState(() => _scanImageBytes = image);
          }
        } on MedicalScanApiException catch (error) {
          if (mounted && error.statusCode != 404) _showError(error.message);
        } on Exception {
          if (mounted) _showError(t('scanImageUnavailable'));
        }
      }
    } on SkinChatApiException catch (error) {
      if (mounted) _showError(error.message);
    }
  }

  Future<Uint8List?> _loadOriginalScanImage(
    SkinChatScanContext scanContext,
  ) async {
    if (!scanContext.hasOriginalImage) return null;
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) {
      throw const SkinChatApiException(
        'Sign in again to load the stored scan image.',
        statusCode: 401,
      );
    }
    final client = http.Client();
    try {
      return await MedicalScanApi(
        baseUrl: widget.baseUrl,
        idToken: token,
        client: client,
      ).originalImage(scanContext.scanId);
    } finally {
      client.close();
    }
  }

  Future<void> _chooseImage() async {
    var conversation = _conversation;
    if (conversation == null) {
      await _startConversation();
      conversation = _conversation;
    }
    if (conversation == null) return;
    if (conversation.hasImage) return;
    final XFile? file;
    try {
      file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 2048,
      );
    } on Object catch (error) {
      if (mounted) {
        showImagePickerFailure(
          context,
          error,
          translate: (key) => AppLocalizations.of(context).text(key),
        );
      }
      return;
    }
    if (file == null) return;
    setState(() {
      _uploading = true;
      _uploadProgress = 0;
    });
    try {
      final updated = await _api.uploadImage(
        conversation.id,
        file,
        language: _language,
        onProgress: (sentBytes, totalBytes) {
          final progress = totalBytes == 0 ? 0.0 : sentBytes / totalBytes;
          if (mounted &&
              (progress * 100).round() != (_uploadProgress * 100).round()) {
            setState(
              () => _uploadProgress = progress.clamp(0, 1).toDouble(),
            );
          }
        },
      );
      final imageBytes = await _api.getImage(conversation.id);
      if (!mounted) return;
      setState(() {
        _conversation = updated;
        _imageBytes = imageBytes;
        _conversations = _conversations
            .map((item) => item.id == updated.id ? updated : item)
            .toList();
        _uploading = false;
      });
      _showError(t('uploaded'));
    } on SkinChatApiException catch (error) {
      if (mounted) {
        setState(() => _uploading = false);
        _showError(error.message);
      }
    }
  }

  Future<void> _sendMessage([String? suggestion]) async {
    final content = (suggestion ?? _messageController.text).trim();
    if (content.isEmpty || _sending || _uploading) {
      return;
    }
    var conversation = _conversation;
    if (conversation == null) {
      await _startConversation();
      conversation = _conversation;
    }
    if (conversation == null) return;
    if (_pendingMessageId == null || _pendingMessageContent != content) {
      _pendingMessageId = DateTime.now().microsecondsSinceEpoch.toString();
      _pendingMessageContent = content;
    }
    final clientMessageId = _pendingMessageId!;
    final pendingMessageId = 'pending-$clientMessageId';
    setState(() {
      if (!_messages.any((message) => message.id == pendingMessageId)) {
        _messages = [
          ..._messages,
          SkinChatMessage(
            id: pendingMessageId,
            role: 'user',
            content: content,
            language: _language,
            createdAt: DateTime.now(),
          ),
        ];
      }
      _sending = true;
      _messageFailed = false;
      if (suggestion == null) _messageController.clear();
    });
    try {
      final (userMessage, reply) = await _api.sendMessage(
        conversation.id,
        content,
        clientMessageId: clientMessageId,
        language: _language,
      );
      if (!mounted) return;
      setState(() {
        _messages = [
          ..._messages.where((message) => message.id != pendingMessageId),
          userMessage,
          reply,
        ];
        _conversation = conversation!.copyWith(updatedAt: reply.createdAt);
        _conversations = _conversations
            .map(
              (item) => item.id == conversation!.id ? _conversation! : item,
            )
            .toList()
          ..sort(
              (first, second) => second.updatedAt.compareTo(first.updatedAt));
        _sending = false;
        _messageFailed = false;
        _pendingMessageId = null;
        _pendingMessageContent = null;
      });
      _scrollToBottom();
    } on SkinChatApiException catch (error) {
      if (mounted) {
        setState(() {
          _sending = false;
          _messageFailed = true;
        });
        _showError(
          error.statusCode == 408 || error.statusCode == 504
              ? t('requestTimeout')
              : error.message,
        );
      }
    } on Exception {
      if (mounted) {
        setState(() {
          _sending = false;
          _messageFailed = true;
        });
        _showError(t('sendFailed'));
      }
    }
  }

  Future<void> _retryMessage() async {
    final content = _pendingMessageContent;
    if (content != null) await _sendMessage(content);
  }

  Future<void> _loadOlderMessages() async {
    final conversation = _conversation;
    final before = _nextBefore;
    if (conversation == null || before == null || _loadingOlder) return;
    setState(() => _loadingOlder = true);
    try {
      final page = await _api.getMessages(conversation.id, before: before);
      if (!mounted) return;
      setState(() {
        _messages = [...page.messages, ..._messages];
        _nextBefore = page.nextBefore;
        _loadingOlder = false;
      });
    } on SkinChatApiException catch (error) {
      if (mounted) {
        setState(() => _loadingOlder = false);
        _showError(error.message);
      }
    }
  }

  Future<void> _showHistory() async {
    try {
      await _refreshConversations();
    } on SkinChatApiException catch (error) {
      if (mounted) _showError(error.message);
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.72,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        t('history'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: t('new'),
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        await _startConversation();
                      },
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _conversations.isEmpty
                    ? Center(child: Text(t('emptyHistory')))
                    : ListView.builder(
                        itemCount: _conversations.length,
                        itemBuilder: (context, index) {
                          final item = _conversations[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  AppDesignTokens.blue.withValues(alpha: .14),
                              child: const Icon(
                                Icons.forum_outlined,
                                color: AppDesignTokens.blue,
                              ),
                            ),
                            title: Text(
                              item.hasImageReference ? t('image') : t('new'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(_formatDate(item.updatedAt)),
                            onTap: () async {
                              Navigator.pop(sheetContext);
                              await _selectConversation(item);
                            },
                            trailing: IconButton(
                              tooltip: t('remove'),
                              onPressed: () => _confirmDelete(item),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(SkinChatConversation item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('remove')),
        content: Text(t('deleteConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.deleteConversation(item.id);
      if (!mounted) return;
      setState(() {
        _conversations.removeWhere((entry) => entry.id == item.id);
        if (_conversation?.id == item.id) {
          _conversation = null;
          _messages = [];
          _imageBytes = null;
          _scanImageBytes = null;
        }
      });
    } on SkinChatApiException catch (error) {
      if (mounted) _showError(error.message);
    }
  }

  Future<void> _deleteMessage(SkinChatMessage message) async {
    final conversation = _conversation;
    if (conversation == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('deleteMessage')),
        content: Text(t('deleteMessageConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final assistantId = message.role == 'user' && message.id.startsWith('user-')
        ? 'assistant-${message.id.substring(5)}'
        : null;
    try {
      await _api.deleteMessage(conversation.id, message.id);
      if (mounted) {
        setState(() {
          _messages.removeWhere(
              (item) => item.id == message.id || item.id == assistantId);
        });
      }
    } on SkinChatApiException catch (error) {
      if (mounted) _showError(error.message);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  TextDirection _messageDirection(String language, String content) {
    if (language == 'ar' || language == 'ku' || language == 'bad') {
      return TextDirection.rtl;
    }
    if (RegExp(r'[\u0600-\u06ff]').hasMatch(content)) {
      return TextDirection.rtl;
    }
    return TextDirection.ltr;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final compactViewport = MediaQuery.sizeOf(context).height < 600;
    final background =
        dark ? AppDesignTokens.darkBackground : AppDesignTokens.lightBackground;
    final panel =
        dark ? AppDesignTokens.darkSurface : AppDesignTokens.lightSurface;
    const accent = AppDesignTokens.blue;
    return Directionality(
      textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: AppElevation.flat,
          scrolledUnderElevation: AppElevation.flat,
          flexibleSpace: const GlassSurface(
            borderRadius: BorderRadius.zero,
            child: SizedBox.expand(),
          ),
          titleSpacing: AppSpacing.x2,
          title: Row(
            children: [
              Container(
                width: AppSpacing.x12 + AppSpacing.x2,
                height: AppSpacing.x12 + AppSpacing.x2,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                  color: AppDesignTokens.blue,
                ),
                child: const Icon(
                  Icons.health_and_safety_outlined,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('title'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      t('subtitle'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: t('history'),
              onPressed: _showHistory,
              icon: const Icon(Icons.history_rounded),
            ),
            IconButton(
              tooltip: t('new'),
              onPressed: _startConversation,
              icon: const Icon(Icons.add_comment_outlined),
            ),
          ],
        ),
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          top: false,
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) => Center(
              child: SizedBox(
                key: const ValueKey('skinchat-content'),
                width: AppBreakpoints.contentWidth(constraints.maxWidth),
                child: Column(
                  children: [
                    Expanded(
                      child: CustomScrollView(
                        controller: _scrollController,
                        slivers: [
                          if (_uploading)
                            SliverToBoxAdapter(
                              child: _uploadProgressIndicator(),
                            ),
                          if (_activeScanContext != null)
                            SliverToBoxAdapter(
                              child: _scanContextCard(panel, accent, dark),
                            ),
                          if (_conversation != null)
                            SliverToBoxAdapter(
                              child: _generalModeNotice(panel),
                            ),
                          if (_conversation?.hasImageReference == true)
                            SliverToBoxAdapter(
                              child: _imageContextCard(panel, accent, dark),
                            ),
                          if (_conversation == null && !_loading)
                            SliverToBoxAdapter(
                              child: _welcomeCard(panel, accent),
                            ),
                          if (_loading)
                            const SliverFillRemaining(
                              hasScrollBody: false,
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: accent,
                                ),
                              ),
                            )
                          else if (_messages.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: _emptyChat(accent),
                            )
                          else
                            _messageList(panel, accent, dark),
                        ],
                      ),
                    ),
                    if (_conversation != null &&
                        _messages.isEmpty &&
                        !keyboardOpen)
                      _suggestions(panel, accent),
                    if (_sending || _messageFailed) _messageStatus(),
                    SafeArea(
                      top: false,
                      left: false,
                      right: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _disclaimer(
                            panel,
                            dark,
                            maxLines: compactViewport ? 1 : 2,
                          ),
                          _inputBar(
                            panel,
                            accent,
                            keyboardOpen: keyboardOpen,
                            maxLines: compactViewport
                                ? 1
                                : keyboardOpen
                                    ? 2
                                    : 4,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _uploadProgressIndicator() => Column(
        children: [
          LinearProgressIndicator(
            value: _uploadProgress,
            minHeight: 2,
            color: AppDesignTokens.blue,
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.x2),
            child: Text(
              '${t('uploading')} ${(_uploadProgress * 100).round()}%',
            ),
          ),
        ],
      );

  Widget _messageStatus() => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.x4,
          AppSpacing.x1,
          AppSpacing.x4,
          AppSpacing.x1,
        ),
        child: Row(
          children: [
            if (_sending)
              const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            if (_sending) const SizedBox(width: AppSpacing.x2),
            Expanded(
              child: Text(
                _sending ? t('sending') : '',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (_messageFailed)
              TextButton.icon(
                onPressed: _retryMessage,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(t('retry')),
              ),
          ],
        ),
      );

  Widget _welcomeCard(Color panel, Color accent) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.x4,
          AppSpacing.x3,
          AppSpacing.x4,
          AppSpacing.x2,
        ),
        child: Material(
          color: panel,
          borderRadius: BorderRadius.circular(AppRadius.extraLarge),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.extraLarge),
            onTap: _startConversation,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.x4),
              child: Row(
                children: [
                  Icon(Icons.add_a_photo_outlined,
                      color: accent, size: AppSpacing.x6),
                  const SizedBox(width: AppSpacing.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('upload'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.x1),
                        Text(
                          t('uploadHint'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _imageContextCard(Color panel, Color accent, bool dark) {
    final conversation = _conversation!;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.x4,
        AppSpacing.x2,
        AppSpacing.x4,
        AppSpacing.x2,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.x3),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(AppRadius.large),
          border: Border.all(
            color: accent.withValues(alpha: dark ? .24 : .18),
          ),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: _imageBytes == null
                  ? null
                  : () => showDialog<void>(
                        context: context,
                        builder: (_) => Dialog(
                          child: ClipRRect(
                            borderRadius:
                                BorderRadius.circular(AppRadius.large),
                            child:
                                Image.memory(_imageBytes!, fit: BoxFit.contain),
                          ),
                        ),
                      ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.medium),
                child: SizedBox(
                  width: AppSpacing.x12 + AppSpacing.x4,
                  height: AppSpacing.x12 + AppSpacing.x4,
                  child: _imageBytes == null
                      ? Icon(Icons.image_outlined, color: accent)
                      : Image.memory(_imageBytes!, fit: BoxFit.cover),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('image'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.x1),
                  Text(
                    conversation.imageUploadTimestamp == null
                        ? t('uploaded')
                        : _formatDate(conversation.imageUploadTimestamp!),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (conversation.hasImageReference &&
                      !conversation.hasImage) ...[
                    const SizedBox(height: AppSpacing.x1),
                    Text(
                      t('imageUnavailable'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (conversation.hasImage &&
                      conversation.initialAnalysis?.isNotEmpty == true) ...[
                    const SizedBox(height: AppSpacing.x1),
                    Text(
                      conversation.initialAnalysis!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: t('new'),
              onPressed: _startConversation,
              icon: const Icon(Icons.add_a_photo_outlined),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scanContextCard(Color panel, Color accent, bool dark) {
    final scan = _activeScanContext!;
    final image = _scanImageBytes;
    final animationDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.x4,
        AppSpacing.x2,
        AppSpacing.x4,
        AppSpacing.x2,
      ),
      child: Semantics(
        key: const ValueKey('attached-scan-card-semantics'),
        container: true,
        button: true,
        expanded: _scanCardExpanded,
        label: t('scanCardSemanticLabel'),
        onTap: _toggleScanCard,
        child: Material(
          color: panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.large),
            side: BorderSide(
              color: accent.withValues(alpha: dark ? .24 : .18),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('attached-scan-card'),
            borderRadius: BorderRadius.circular(AppRadius.large),
            onTap: _toggleScanCard,
            child: AnimatedSize(
              duration: animationDuration,
              curve: Curves.easeInOut,
              alignment: AlignmentDirectional.topCenter,
              child: _scanCardExpanded
                  ? ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.6,
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.x3),
                        child: _expandedScanCard(scan, image, accent),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(AppSpacing.x3),
                      child: _collapsedScanCard(scan, image, accent),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _collapsedScanCard(
    SkinChatScanContext scan,
    Uint8List? image,
    Color accent,
  ) {
    final metadata = [
      _formatDate(scan.scanDate),
      if (scan.bodyLocation?.isNotEmpty == true) scan.bodyLocation!,
    ].join(' · ');
    final preview = scan.summary?.trim().isNotEmpty == true
        ? _scanSummaryPreview(scan.summary!)
        : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _scanThumbnail(
          image,
          accent,
          56,
          onTap: image == null ? null : _toggleScanCard,
        ),
        const SizedBox(width: AppSpacing.x2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${t('condition')}: ${scan.detectedCondition}',
                key: const ValueKey('attached-scan-title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                metadata,
                key: const ValueKey('attached-scan-metadata'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (preview != null)
                Text(
                  preview,
                  key: const ValueKey('attached-scan-summary-preview'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              Text(
                t('scanCardCompactDisclaimer'),
                key: const ValueKey('attached-scan-compact-disclaimer'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: t('scanCardShowMore'),
          onPressed: _toggleScanCard,
          style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
          icon: const Icon(Icons.expand_more_rounded),
        ),
      ],
    );
  }

  Widget _expandedScanCard(
    SkinChatScanContext scan,
    Uint8List? image,
    Color accent,
  ) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _scanThumbnail(
            image,
            accent,
            72,
            onTap: image == null ? null : () => _showScanImage(image),
          ),
          const SizedBox(width: AppSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        t('scanAttached'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      tooltip: t('scanCardShowLess'),
                      onPressed: _toggleScanCard,
                      style:
                          IconButton.styleFrom(minimumSize: const Size(48, 48)),
                      icon: const Icon(Icons.expand_less_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.x1),
                SelectableText('${t('scanId')}: ${scan.scanId}'),
                Text('${t('condition')}: ${scan.detectedCondition}'),
                Text('${t('possiblePattern')}: ${scan.detectedCondition}'),
                Text('${t('scanDate')}: ${_formatDate(scan.scanDate)}'),
                if (scan.bodyLocation?.isNotEmpty == true)
                  Text('${t('bodyLocation')}: ${scan.bodyLocation}'),
                if (scan.summary?.isNotEmpty == true) ...[
                  const SizedBox(height: AppSpacing.x2),
                  MarkdownBody(data: scan.summary!),
                ],
                if (image == null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.x2),
                    child: Text(
                      t('scanImageUnavailable'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.x2),
                  child: Text(
                    t('screeningDisclaimer'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _scanThumbnail(
    Uint8List? image,
    Color accent,
    double size, {
    VoidCallback? onTap,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          child: SizedBox(
            width: size,
            height: size,
            child: image == null
                ? Icon(Icons.image_not_supported_outlined, color: accent)
                : Image.memory(image, fit: BoxFit.cover),
          ),
        ),
      );

  void _showScanImage(Uint8List image) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.large),
          child: Image.memory(image, fit: BoxFit.contain),
        ),
      ),
    );
  }

  void _toggleScanCard() {
    setState(() => _scanCardExpanded = !_scanCardExpanded);
  }

  String _scanSummaryPreview(String summary) {
    final text = summary
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1')
        .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '')
        .replaceAll(RegExp(r'^\s{0,3}>\s*', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*-\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*\+\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*\*\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '')
        .replaceAll(RegExp(r'[*_`~]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final sentenceEnd = RegExp(r'[.!?](?=\s|$)').firstMatch(text);
    if (sentenceEnd != null && sentenceEnd.end <= 140) {
      return text.substring(0, sentenceEnd.end);
    }
    if (text.length <= 140) return text;
    return '${text.substring(0, 137).trimRight()}…';
  }

  Widget _generalModeNotice(Color panel) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.x4,
          AppSpacing.x2,
          AppSpacing.x4,
          AppSpacing.x1,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.x3),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(AppRadius.medium),
            border: Border.all(
              color: AppDesignTokens.blue.withValues(alpha: .18),
            ),
          ),
          child: Text(
            t('generalMode'),
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.start,
          ),
        ),
      );

  Widget _emptyChat(Color accent) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline_rounded,
                size: AppSpacing.x8,
                color: accent,
              ),
              const SizedBox(height: AppSpacing.x3),
              Text(t('emptyChat'), textAlign: TextAlign.center),
            ],
          ),
        ),
      );

  Widget _messageList(Color panel, Color accent, bool dark) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x4,
          AppSpacing.x2,
          AppSpacing.x4,
          AppSpacing.x4,
        ),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              if (_nextBefore != null && index == 0) {
                return Center(
                  child: TextButton(
                    onPressed: _loadingOlder ? null : _loadOlderMessages,
                    child: _loadingOlder
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(t('older')),
                  ),
                );
              }
              final messageIndex = index - (_nextBefore == null ? 0 : 1);
              final message = _messages[messageIndex];
              final isUser = message.role == 'user';
              final messageColor = isUser
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurface;
              return Align(
                key: ValueKey('skinchat-message-${message.id}'),
                alignment: isUser
                    ? AlignmentDirectional.centerEnd
                    : AlignmentDirectional.centerStart,
                child: GestureDetector(
                  onLongPress: () => _deleteMessage(message),
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: AppBreakpoints.fromWidth(
                                MediaQuery.sizeOf(context).width,
                              ) ==
                              AppViewport.expanded
                          ? 760
                          : MediaQuery.sizeOf(context).width * .84,
                    ),
                    margin: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      AppSpacing.x3,
                      AppSpacing.x3,
                      AppSpacing.x3,
                      AppSpacing.x2,
                    ),
                    decoration: BoxDecoration(
                      color: isUser ? accent : panel,
                      borderRadius: BorderRadiusDirectional.only(
                        topStart: const Radius.circular(18),
                        topEnd: const Radius.circular(18),
                        bottomStart: Radius.circular(isUser ? 18 : 5),
                        bottomEnd: Radius.circular(isUser ? 5 : 18),
                      ),
                      border: isUser
                          ? null
                          : Border.all(
                              color: accent.withValues(alpha: dark ? .14 : .12),
                            ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Directionality(
                          textDirection: _messageDirection(
                              message.language, message.content),
                          child: MarkdownBody(
                            data: message.content,
                            selectable: true,
                            imageBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                            styleSheet: MarkdownStyleSheet(
                              p: TextStyle(color: messageColor, height: 1.45),
                              h1: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(color: messageColor),
                              h2: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(color: messageColor),
                              h3: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(color: messageColor),
                              strong: TextStyle(
                                color: messageColor,
                                fontWeight: FontWeight.w800,
                              ),
                              em: TextStyle(
                                color: messageColor,
                                fontStyle: FontStyle.italic,
                              ),
                              listBullet: TextStyle(color: messageColor),
                              code: TextStyle(
                                color: messageColor,
                                backgroundColor:
                                    isUser ? Colors.white24 : panel,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.x1),
                        Text(
                          '${message.createdAt.toLocal().hour.toString().padLeft(2, '0')}:'
                          '${message.createdAt.toLocal().minute.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            color: isUser
                                ? Colors.white70
                                : Theme.of(context).textTheme.bodySmall?.color,
                            fontSize: AppTypography.caption,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
            childCount: _messages.length + (_nextBefore == null ? 0 : 1),
          ),
        ),
      );

  Widget _suggestions(Color panel, Color accent) {
    const suggestions = ['suggest1', 'suggest2', 'suggest3'];
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.x4,
        0,
        AppSpacing.x4,
        AppSpacing.x1,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < suggestions.length; index++) ...[
              if (index > 0) const SizedBox(width: AppSpacing.x2),
              ActionChip(
                backgroundColor: panel,
                side: BorderSide(
                  color: accent.withValues(alpha: .3),
                ),
                label: Text(
                  t(suggestions[index]),
                  maxLines: 1,
                  softWrap: false,
                ),
                onPressed: _sending || _messageFailed
                    ? null
                    : () => _sendMessage(t(suggestions[index])),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _disclaimer(
    Color panel,
    bool dark, {
    required int maxLines,
  }) =>
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.x4,
          AppSpacing.x1,
          AppSpacing.x4,
          AppSpacing.x1,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 15,
              color: dark ? Colors.white54 : Colors.black54,
            ),
            const SizedBox(width: AppSpacing.x2),
            Expanded(
              child: Text(
                t('disclaimer'),
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
      );

  Widget _inputBar(
    Color panel,
    Color accent, {
    required bool keyboardOpen,
    required int maxLines,
  }) {
    final enabled = _conversation != null &&
        !_sending &&
        !_uploading &&
        !_loading &&
        !_messageFailed;
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: AppSpacing.x3,
        end: AppSpacing.x3,
        top: AppSpacing.x1,
        bottom: keyboardOpen ? AppSpacing.x1 : AppSpacing.x2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton.filledTonal(
            tooltip: t('upload'),
            onPressed: _uploading ? null : _chooseImage,
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
          const SizedBox(width: AppSpacing.x2),
          Expanded(
            child: TextField(
              controller: _messageController,
              enabled: enabled,
              minLines: 1,
              maxLines: maxLines,
              textDirection: _messageDirection('', _messageController.text),
              onChanged: (value) {
                if (_pendingMessageContent != null &&
                    value.trim() != _pendingMessageContent) {
                  _pendingMessageId = null;
                  _pendingMessageContent = null;
                  _messageFailed = false;
                }
                setState(() {});
              },
              onSubmitted: enabled ? (_) => _sendMessage() : null,
              decoration: InputDecoration(
                hintText: t('placeholder'),
                filled: true,
                fillColor: panel,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.x2),
          IconButton.filled(
            tooltip: t('send'),
            onPressed: enabled ? _sendMessage : null,
            style: IconButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
            ),
            icon: _sending
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }
}
