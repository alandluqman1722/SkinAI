import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
    'notAnalyzed': 'Images are not sent to Gemini or analyzed.',
    'remove': 'Delete conversation',
    'cancel': 'Cancel',
    'delete': 'Delete',
    'deleteMessage': 'Delete message',
    'deleteConfirm': 'Delete this conversation and its stored image?',
    'deleteMessageConfirm': 'Delete this message and its paired reply?',
    'emptyHistory': 'No conversations yet.',
    'emptyChat': 'Your conversation will appear here.',
    'placeholder': 'Ask a skincare question…',
    'send': 'Send message',
    'sending': 'SkinChat is responding…',
    'older': 'Load older messages',
    'retry': 'Try again',
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
    'notAnalyzed': 'وێنەکان بۆ Gemini نانێردرێن و شیکاری ناکرێن.',
    'remove': 'سڕینەوەی گفتوگۆ',
    'cancel': 'پاشگەزبوونەوە',
    'delete': 'بسڕەوە',
    'deleteMessage': 'سڕینەوەی نامە',
    'deleteConfirm': 'ئەم گفتوگۆیە و وێنە هەڵگیراوەکەی بسڕێتەوە؟',
    'deleteMessageConfirm': 'ئەم نامەیە و وەڵامەکەی بسڕێتەوە؟',
    'emptyHistory': 'هێشتا هیچ گفتوگۆیەک نییە.',
    'emptyChat': 'گفتوگۆکەت لێرە دەردەکەوێت.',
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
    'notAnalyzed': 'وێنە بۆ Gemini ناهێنە فرێکرن و شیکاری ناهێنە کرن.',
    'remove': 'گفتوگۆیێ ژێببە',
    'cancel': 'بتال بکە',
    'delete': 'ژێببە',
    'deleteMessage': 'نامەیێ ژێببە',
    'deleteConfirm': 'ئەرێ ئەڤ گفتوگۆ و وێنەیا هەڵگیرا ژێببەم؟',
    'deleteMessageConfirm': 'ئەرێ ئەڤ نامە و بەرسڤا وێ ژێببەم؟',
    'emptyHistory': 'هێشتا چ گفتوگۆ نینە.',
    'emptyChat': 'گفتوگۆیا تە ل ڤێرێ دیار دبیت.',
    'placeholder': 'پرسیارەکا دەر بارێ چاڤدێریا پێستی بکە…',
    'send': 'پرسیارێ بفرێکە',
    'sending': 'SkinChat بەرسڤ ددەت…',
    'older': 'نامەیێن کەڤن بارکە',
    'retry': 'دووبارە هەول بدە',
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
    'notAnalyzed': 'لا تُرسل الصور إلى Gemini ولا تُحلل.',
    'remove': 'حذف المحادثة',
    'cancel': 'إلغاء',
    'delete': 'حذف',
    'deleteMessage': 'حذف الرسالة',
    'deleteConfirm': 'هل تريد حذف هذه المحادثة والصورة المخزنة؟',
    'deleteMessageConfirm': 'هل تريد حذف هذه الرسالة والرد المرتبط بها؟',
    'emptyHistory': 'لا توجد محادثات بعد.',
    'emptyChat': 'ستظهر محادثتك هنا.',
    'placeholder': 'اسأل عن العناية بالبشرة…',
    'send': 'إرسال الرسالة',
    'sending': 'SkinChat يكتب…',
    'older': 'تحميل الرسائل الأقدم',
    'retry': 'حاول مرة أخرى',
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
  },
};

class SkinChatScreen extends StatefulWidget {
  const SkinChatScreen({
    required this.baseUrl,
    required this.languageCode,
    super.key,
  });

  final String baseUrl;
  final String languageCode;

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
  String? _nextBefore;
  bool _loading = true;
  bool _uploading = false;
  double _uploadProgress = 0;
  bool _sending = false;
  bool _loadingOlder = false;
  bool _messageFailed = false;
  String? _pendingMessageId;
  String? _pendingMessageContent;

  String get _language =>
      _copy.containsKey(widget.languageCode) ? widget.languageCode : 'en';
  String t(String key) => _copy[_language]![key]!;

  bool get _rtl => _language != 'en';

  @override
  void initState() {
    super.initState();
    _api = SkinChatApiService(
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
      if (conversations.isNotEmpty) {
        await _selectConversation(conversations.first);
      }
    } on SkinChatApiException catch (error) {
      if (mounted) {
        setState(() => _loading = false);
        _showError(error.message);
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
      _nextBefore = null;
    });
    try {
      final page = await _api.getMessages(conversation.id);
      Uint8List? imageBytes;
      if (conversation.hasImage) {
        try {
          imageBytes = await _api.getImage(conversation.id);
        } on SkinChatApiException catch (error) {
          if (error.statusCode != 404) rethrow;
          selectedConversation = conversation.copyWith(imageAvailable: false);
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
      final conversation = await _api.createConversation();
      if (!mounted) return;
      setState(() {
        _conversations = [conversation, ..._conversations];
        _conversation = conversation;
        _messages = [];
        _imageBytes = null;
        _nextBefore = null;
      });
      await _chooseImage();
    } on SkinChatApiException catch (error) {
      if (mounted) _showError(error.message);
    }
  }

  Future<void> _chooseImage() async {
    final conversation = _conversation;
    if (conversation == null) {
      await _startConversation();
      return;
    }
    if (conversation.hasImage) return;
    final XFile? file;
    try {
      file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 2048,
      );
    } on Exception catch (error) {
      if (mounted) _showError('Could not open the image picker: $error');
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
    final conversation = _conversation;
    final content = (suggestion ?? _messageController.text).trim();
    if (conversation == null ||
        !conversation.hasImageReference ||
        content.isEmpty ||
        _sending) {
      return;
    }
    if (_pendingMessageId == null || _pendingMessageContent != content) {
      _pendingMessageId = DateTime.now().microsecondsSinceEpoch.toString();
      _pendingMessageContent = content;
    }
    final clientMessageId = _pendingMessageId!;
    setState(() => _sending = true);
    try {
      final (userMessage, reply) = await _api.sendMessage(
        conversation.id,
        content,
        clientMessageId: clientMessageId,
        language: _language,
      );
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, userMessage, reply];
        if (suggestion == null || _messageController.text.trim() == content) {
          _messageController.clear();
        }
        _sending = false;
        _messageFailed = false;
        _pendingMessageId = null;
        _pendingMessageContent = null;
      });
      await _refreshConversations();
      _scrollToBottom();
    } on SkinChatApiException catch (error) {
      if (mounted) {
        setState(() {
          _sending = false;
          _messageFailed = true;
        });
        _showError(
          error.statusCode == 408 ? t('requestTimeout') : error.message,
        );
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
                              backgroundColor: const Color(0xFF00C9E8)
                                  .withValues(alpha: .14),
                              child: const Icon(
                                Icons.forum_outlined,
                                color: Color(0xFF00A8D0),
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
    final background = dark ? const Color(0xFF07111F) : const Color(0xFFF4F8FC);
    final panel = dark ? const Color(0xFF101D2D) : Colors.white;
    const accent = Color(0xFF12C7E8);
    return Directionality(
      textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: background,
        appBar: AppBar(
          backgroundColor: background,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 8,
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF13C7E8), Color(0xFF5865E8)],
                  ),
                ),
                child: const Icon(
                  Icons.health_and_safety_outlined,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 11),
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
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              if (_uploading)
                Column(
                  children: [
                    LinearProgressIndicator(
                      value: _uploadProgress,
                      minHeight: 2,
                      color: const Color(0xFF12C7E8),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        '${t('uploading')} ${(_uploadProgress * 100).round()}%',
                      ),
                    ),
                  ],
                ),
              if (_conversation != null) _imageContextCard(panel, accent, dark),
              if (_conversation == null && !_loading)
                _welcomeCard(panel, accent),
              if (_loading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF12C7E8),
                    ),
                  ),
                )
              else
                Expanded(
                  child: _messages.isEmpty
                      ? _emptyChat(panel, dark)
                      : _messageList(panel, accent, dark),
                ),
              if (_conversation?.hasImageReference == true && _messages.isEmpty)
                _suggestions(panel),
              if (_sending || _messageFailed)
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 2, 16, 6),
                  child: Row(
                    children: [
                      if (_sending)
                        const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      if (_sending) const SizedBox(width: 8),
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
                ),
              _disclaimer(panel, dark),
              _inputBar(panel, accent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _welcomeCard(Color panel, Color accent) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Material(
          color: panel,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: _startConversation,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Icon(Icons.add_a_photo_outlined, color: accent, size: 30),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('upload'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
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
      padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 14, 8),
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(19),
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
                            borderRadius: BorderRadius.circular(18),
                            child:
                                Image.memory(_imageBytes!, fit: BoxFit.contain),
                          ),
                        ),
                      ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: _imageBytes == null
                      ? Icon(Icons.image_outlined, color: accent)
                      : Image.memory(_imageBytes!, fit: BoxFit.cover),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('image'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    conversation.imageUploadTimestamp == null
                        ? t('uploaded')
                        : _formatDate(conversation.imageUploadTimestamp!),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (conversation.hasImageReference &&
                      !conversation.hasImage) ...[
                    const SizedBox(height: 4),
                    Text(
                      t('imageUnavailable'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (conversation.hasImage &&
                      conversation.initialAnalysis?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
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

  Widget _emptyChat(Color panel, bool dark) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 20),
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 42,
            color: const Color(0xFF12C7E8).withValues(alpha: .8),
          ),
          const SizedBox(height: 12),
          Text(t('emptyChat'), textAlign: TextAlign.center),
        ],
      );

  Widget _messageList(Color panel, Color accent, bool dark) => ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemCount: _messages.length + (_nextBefore == null ? 0 : 1),
        itemBuilder: (context, index) {
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
          return Align(
            alignment: isUser
                ? AlignmentDirectional.centerEnd
                : AlignmentDirectional.centerStart,
            child: GestureDetector(
              onLongPress: () => _deleteMessage(message),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * .84,
                ),
                margin: const EdgeInsets.symmetric(vertical: 5),
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                decoration: BoxDecoration(
                  color: isUser ? const Color(0xFF1469E8) : panel,
                  borderRadius: BorderRadius.circular(18).copyWith(
                    bottomRight: isUser ? const Radius.circular(5) : null,
                    bottomLeft: isUser ? null : const Radius.circular(5),
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
                      textDirection:
                          _messageDirection(message.language, message.content),
                      child: SelectableText(
                        message.content,
                        style: TextStyle(
                          color: isUser
                              ? Colors.white
                              : Theme.of(context).colorScheme.onSurface,
                          height: 1.45,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${message.createdAt.toLocal().hour.toString().padLeft(2, '0')}:'
                      '${message.createdAt.toLocal().minute.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: isUser
                            ? Colors.white70
                            : Theme.of(context).textTheme.bodySmall?.color,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

  Widget _suggestions(Color panel) {
    const suggestions = ['suggest1', 'suggest2', 'suggest3'];
    return SizedBox(
      height: 42,
      child: ListView.separated(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 5),
        scrollDirection: Axis.horizontal,
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) => ActionChip(
          backgroundColor: panel,
          side:
              BorderSide(color: const Color(0xFF12C7E8).withValues(alpha: .3)),
          label: Text(t(suggestions[index])),
          onPressed:
              _sending ? null : () => _sendMessage(t(suggestions[index])),
        ),
      ),
    );
  }

  Widget _disclaimer(Color panel, bool dark) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 7),
        child: Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 15,
              color: dark ? Colors.white54 : Colors.black54,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                t('disclaimer'),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
      );

  Widget _inputBar(Color panel, Color accent) {
    final enabled =
        _conversation?.hasImageReference == true && !_sending && !_uploading;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        12,
        5,
        12,
        MediaQuery.viewInsetsOf(context).bottom > 0 ? 8 : 12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton.filledTonal(
            tooltip: t('upload'),
            onPressed: _uploading ? null : _chooseImage,
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _messageController,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
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
                hintText: _conversation?.hasImageReference == true
                    ? t('placeholder')
                    : t('uploadHint'),
                filled: true,
                fillColor: panel,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 7),
          IconButton.filled(
            tooltip: t('send'),
            onPressed: enabled ? _sendMessage : null,
            style: IconButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: const Color(0xFF06202B),
            ),
            icon: _sending
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF06202B),
                    ),
                  )
                : const Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }
}
