import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import 'package:skin_ai/design/app_design_system.dart';
import 'package:skin_ai/doctors/doctor_screens.dart';
import 'package:skin_ai/localization/app_localizations.dart';
import 'package:skin_ai/medical_assessment/medical_assessment_api.dart';
import 'package:skin_ai/medical_assessment/medical_assessment_pdf.dart';

class MedicalAssessmentScreen extends StatefulWidget {
  const MedicalAssessmentScreen({
    required this.skinImage,
    required this.skinFilename,
    required this.baseUrl,
    required this.tokenProvider,
    this.initialResult,
    this.bodyLocation = '',
    this.symptomsDuration = '',
    this.symptomsDetails = '',
    super.key,
  });

  final Uint8List skinImage;
  final String skinFilename;
  final String baseUrl;
  final AssessmentTokenProvider tokenProvider;
  final MedicalAssessmentResult? initialResult;
  final String bodyLocation;
  final String symptomsDuration;
  final String symptomsDetails;

  @override
  State<MedicalAssessmentScreen> createState() =>
      _MedicalAssessmentScreenState();
}

class _MedicalAssessmentScreenState extends State<MedicalAssessmentScreen> {
  static const _maxAttachmentBytes = 8 * 1024 * 1024;
  static const _maxTotalBytes = 30 * 1024 * 1024;
  static const _maxReportCount = 3;

  final _formKey = GlobalKey<FormState>();
  final _ageController = TextEditingController();
  final _allergiesController = TextEditingController();
  final _historyController = TextEditingController();
  final _durationController = TextEditingController();
  final _symptomsController = TextEditingController();
  final _medicationDurationController = TextEditingController();
  final _medicationNameController = TextEditingController();
  final _examinationDateController = TextEditingController();
  final _examinationFindingsController = TextEditingController();
  final _examinationDiagnosisController = TextEditingController();
  late final MedicalAssessmentApi _api;
  final List<AssessmentFileUpload> _reports = [];
  Uint8List? _medicationImage;
  String? _medicationFilename;
  String? _sex;
  String _pregnancyStatus = 'unsure';
  String? _medicationPrescribed;
  String? _medicationEffect;
  String? _medicationStatus;
  String? _examinationStatus;
  bool _storageConsent = false;
  bool _processing = false;
  bool _submissionStarting = false;
  bool _exporting = false;
  int _step = 0;
  double _uploadProgress = 0;
  String? _error;
  MedicalAssessmentResult? _result;

  AppLocalizations get _localizations => AppLocalizations.of(context);
  String _t(String key) =>
      _localizations.text(key, domain: 'medical_assessment');
  String _appT(String key) => _localizations.text(key);

  @override
  void initState() {
    super.initState();
    _api = MedicalAssessmentApi(
      baseUrl: widget.baseUrl,
      tokenProvider: widget.tokenProvider,
    );
    _result = widget.initialResult;
    _durationController.text = widget.symptomsDuration;
    _symptomsController.text = widget.symptomsDetails;
  }

  @override
  void dispose() {
    _api.close();
    _ageController.dispose();
    _allergiesController.dispose();
    _historyController.dispose();
    _durationController.dispose();
    _symptomsController.dispose();
    _medicationDurationController.dispose();
    _medicationNameController.dispose();
    _examinationDateController.dispose();
    _examinationFindingsController.dispose();
    _examinationDiagnosisController.dispose();
    super.dispose();
  }

  void _notice(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickMedication(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 90,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty || bytes.length > _maxAttachmentBytes) {
        _notice(_t('uploadError'));
        return;
      }
      if (!mounted) return;
      setState(() {
        _medicationImage = bytes;
        _medicationFilename = file.name;
        _error = null;
      });
    } on Exception {
      if (mounted) _notice(_t('uploadError'));
    }
  }

  Future<void> _chooseMedicationImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text(_appT('camera')),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(_appT('gallery')),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _pickMedication(source);
  }

  Future<void> _addReportImages(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1800,
        imageQuality: 92,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final mimeType = _mimeType(file.name);
      if (bytes.isEmpty ||
          bytes.length > _maxAttachmentBytes ||
          !{'image/jpeg', 'image/png', 'image/webp'}.contains(mimeType)) {
        _notice(_t('uploadError'));
        return;
      }
      _appendReports([
        AssessmentFileUpload(
          bytes: bytes,
          filename: file.name,
          mimeType: mimeType,
        ),
      ]);
    } on Exception {
      if (mounted) _notice(_t('uploadError'));
    }
  }

  Future<void> _chooseReportFiles() async {
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
        allowMultiple: true,
        withData: true,
      );
      if (selection == null) return;
      final files = <AssessmentFileUpload>[];
      for (final file in selection.files) {
        final bytes = file.bytes;
        if (bytes == null ||
            bytes.isEmpty ||
            bytes.length > _maxAttachmentBytes) {
          _notice(_t('uploadError'));
          return;
        }
        files.add(
          AssessmentFileUpload(
            bytes: bytes,
            filename: file.name,
            mimeType: _mimeType(file.name),
          ),
        );
      }
      _appendReports(files);
    } on Exception {
      if (mounted) _notice(_t('uploadError'));
    }
  }

  Future<void> _chooseReportSource() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text(_appT('camera')),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(_appT('gallery')),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: Text(_t('addReport')),
              onTap: () => Navigator.pop(context, 'files'),
            ),
          ],
        ),
      ),
    );
    switch (source) {
      case 'camera':
        await _addReportImages(ImageSource.camera);
        break;
      case 'gallery':
        await _addReportImages(ImageSource.gallery);
        break;
      case 'files':
        await _chooseReportFiles();
        break;
      case null:
        return;
    }
  }

  void _appendReports(List<AssessmentFileUpload> files) {
    if (files.isEmpty) return;
    final newTotal = _reports.length + files.length;
    final totalBytes = _reports.fold<int>(
          0,
          (sum, report) => sum + report.bytes.length,
        ) +
        files.fold<int>(0, (sum, report) => sum + report.bytes.length) +
        widget.skinImage.length +
        (_medicationImage?.length ?? 0);
    if (newTotal > _maxReportCount || totalBytes > _maxTotalBytes) {
      _notice(_t('uploadError'));
      return;
    }
    setState(() {
      _reports.addAll(files);
      _error = null;
    });
  }

  String _mimeType(String filename) {
    final extension = filename.toLowerCase().split('.').last;
    return switch (extension) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
  }

  List<String> _enteredLines(TextEditingController controller) =>
      controller.text
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();

  bool get _hasStructuredExamination =>
      _examinationDateController.text.trim().isNotEmpty ||
      _examinationFindingsController.text.trim().isNotEmpty ||
      _examinationDiagnosisController.text.trim().isNotEmpty;

  bool _validateAnswers() {
    if (!(_formKey.currentState?.validate() ?? false)) return false;
    if (_step == 0 && _sex == null) {
      setState(() => _error = _t('selectOption'));
      return false;
    }
    if (_step == 1 && _medicationStatus == null) {
      setState(() => _error = _t('selectOption'));
      return false;
    }
    if (_step == 2 && _examinationStatus == null) {
      setState(() => _error = _t('selectOption'));
      return false;
    }
    final needsMedicationEvidence = _medicationImage == null &&
        _medicationNameController.text.trim().isEmpty;
    if (_step == 1 && _medicationStatus == 'yes' && needsMedicationEvidence) {
      setState(() => _error = _t('uploadError'));
      return false;
    }
    if (_step == 2 &&
        _examinationStatus == 'yes' &&
        _reports.isEmpty &&
        !_hasStructuredExamination) {
      setState(() => _error = _t('uploadError'));
      return false;
    }
    return true;
  }

  void _continue() {
    if (!_validateAnswers()) return;
    setState(() {
      _step++;
      _error = null;
    });
  }

  void _goBackOrClose() {
    if (_result != null || _step == 0) {
      Navigator.pop(context, _result);
      return;
    }
    setState(() {
      _step--;
      _error = null;
    });
  }

  Future<bool> _requestProcessingConsent() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('processingConsentTitle')),
        content: SingleChildScrollView(
          child: Text(_t('processingConsentBody')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_appT('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_t('consentContinue')),
          ),
        ],
      ),
    );
    return accepted == true;
  }

  Future<void> _submit() async {
    if (_processing || _submissionStarting || !_validateAnswers()) return;
    _submissionStarting = true;
    try {
      if (!await _requestProcessingConsent() || !mounted) return;
      final age = int.tryParse(_ageController.text.trim());
      if (age == null) {
        setState(() => _error = _t('ageHint'));
        return;
      }
      final languageCode = _localizations.locale.languageCode;
      setState(() {
        _processing = true;
        _uploadProgress = 0;
        _error = null;
      });
      final result = await _api.createAssessment(
        MedicalAssessmentUpload(
          patientData: {
            'age': age,
            'sex': _sex,
            'language': switch (languageCode) {
              'ku' || 'ckb' => 'ku',
              'bad' || 'kmr' => 'bad',
              'ar' => 'ar',
              _ => 'en',
            },
            'allergies': _allergiesController.text.trim(),
            'medical_history': _historyController.text.trim(),
            'pregnancy_or_breastfeeding': _pregnancyStatus,
            'symptoms_duration': _durationController.text.trim(),
            'symptoms_details': _symptomsController.text.trim(),
            'body_location': widget.bodyLocation,
            'taking_medication': _medicationStatus == 'yes',
            'medication_status': _medicationStatus,
            if (_medicationStatus == 'yes') ...{
              if (_medicationNameController.text.trim().isNotEmpty)
                'medication_name': _medicationNameController.text.trim(),
              'medication_duration': _medicationDurationController.text.trim(),
              'medication_prescribed': _medicationPrescribed,
              'medication_effect': _medicationEffect,
            },
            'had_examinations': _examinationStatus == 'yes',
            'examination_status': _examinationStatus,
            'structured_examinations': _hasStructuredExamination
                ? [
                    {
                      'examination_date':
                          _examinationDateController.text.trim().isEmpty
                              ? null
                              : _examinationDateController.text.trim(),
                      'doctor_findings':
                          _enteredLines(_examinationFindingsController),
                      'documented_diagnosis':
                          _enteredLines(_examinationDiagnosisController),
                    },
                  ]
                : <Map<String, Object?>>[],
            'external_processing_consent': true,
            'storage_consent': _storageConsent,
          },
          skinImage: widget.skinImage,
          skinFilename: widget.skinFilename,
          medicationImage: _medicationImage,
          medicationFilename: _medicationFilename,
          reports: List.unmodifiable(_reports),
        ),
        onProgress: (sent, total) {
          if (!mounted || total == 0) return;
          setState(
            () => _uploadProgress = (sent / total).clamp(0, 1).toDouble(),
          );
        },
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _processing = false;
      });
    } on MedicalAssessmentApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _error = error.message;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _error = _t('assessmentFailed');
      });
    } finally {
      _submissionStarting = false;
    }
  }

  Widget _sectionTitle(String title, IconData icon) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.x3),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: AppSpacing.x2),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      );

  Widget _card({required Widget child}) => Card(
        margin: const EdgeInsets.only(bottom: AppSpacing.x4),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x4),
          child: child,
        ),
      );

  Widget _triQuestion({
    required String title,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.x2),
          Wrap(
            spacing: AppSpacing.x2,
            runSpacing: AppSpacing.x2,
            children: [
              for (final option in [
                ('yes', _appT('yes')),
                ('no', _appT('no')),
                ('unsure', _t('unsure')),
              ])
                ChoiceChip(
                  label: Text(option.$2),
                  selected: value == option.$1,
                  onSelected: (_) => onChanged(option.$1),
                ),
            ],
          ),
        ],
      );

  Widget _dropdown({
    required String label,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
    bool requiredField = true,
  }) =>
      DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: items,
        validator: requiredField
            ? (selected) => selected == null ? _t('selectOption') : null
            : null,
        onChanged: onChanged,
      );

  DropdownMenuItem<String> _option(String value, String label) =>
      DropdownMenuItem(value: value, child: Text(label));

  List<DropdownMenuItem<String>> _pregnancyOptions() => [
        _option('not_applicable', _t('pregnancy_not_applicable')),
        _option('pregnant', _t('pregnancy_pregnant')),
        _option('breastfeeding', _t('pregnancy_breastfeeding')),
        _option('neither', _t('pregnancy_neither')),
        _option('unsure', _t('pregnancy_unsure')),
      ];

  Widget _buildForm() => LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth =
              constraints.maxWidth > 760 ? 760.0 : constraints.maxWidth;
          return Center(
            child: SizedBox(
              width: contentWidth,
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.x4),
                  children: [
                    Text(
                      _t('stepProgress')
                          .replaceFirst(
                            '{step}',
                            '${_step + 1}',
                          )
                          .replaceFirst('{total}', '3'),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: AppSpacing.x2),
                    LinearProgressIndicator(value: (_step + 1) / 3),
                    const SizedBox(height: AppSpacing.x3),
                    Text(
                      _t([
                        'stepPatient',
                        'stepMedication',
                        'stepExaminations',
                      ][_step]),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.x2),
                    Text(
                      _t('intro'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.x4),
                    if (_step == 0)
                      _card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _sectionTitle(
                              _t('patientInformation'),
                              Icons.person_outline,
                            ),
                            TextFormField(
                              controller: _ageController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(3),
                              ],
                              decoration: InputDecoration(
                                labelText: _t('age'),
                                hintText: _t('ageHint'),
                                border: const OutlineInputBorder(),
                              ),
                              validator: (value) {
                                final age = int.tryParse(value?.trim() ?? '');
                                return age == null || age < 1 || age > 120
                                    ? _t('ageHint')
                                    : null;
                              },
                            ),
                            const SizedBox(height: AppSpacing.x3),
                            _dropdown(
                              label: _t('sex'),
                              value: _sex,
                              items: [
                                _option('female', _t('female')),
                                _option('male', _t('male')),
                                _option('intersex', _t('intersex')),
                                _option('prefer_not_to_say', _t('preferNot')),
                              ],
                              onChanged: (value) =>
                                  setState(() => _sex = value),
                            ),
                            const SizedBox(height: AppSpacing.x3),
                            _dropdown(
                              label: _t('pregnancy'),
                              value: _pregnancyStatus,
                              items: _pregnancyOptions(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _pregnancyStatus = value);
                                }
                              },
                            ),
                            const SizedBox(height: AppSpacing.x3),
                            TextFormField(
                              controller: _allergiesController,
                              maxLength: 2000,
                              maxLines: 2,
                              decoration: InputDecoration(
                                labelText: _t('allergies'),
                                border: const OutlineInputBorder(),
                                counterText: '',
                              ),
                            ),
                            const SizedBox(height: AppSpacing.x3),
                            TextFormField(
                              controller: _historyController,
                              maxLength: 3000,
                              maxLines: 3,
                              decoration: InputDecoration(
                                labelText: _t('medicalHistory'),
                                border: const OutlineInputBorder(),
                                counterText: '',
                              ),
                            ),
                            const SizedBox(height: AppSpacing.x3),
                            TextFormField(
                              controller: _durationController,
                              maxLength: 200,
                              decoration: InputDecoration(
                                labelText: _t('symptomsDuration'),
                                border: const OutlineInputBorder(),
                                counterText: '',
                              ),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                      ? _t('symptomsDuration')
                                      : null,
                            ),
                            const SizedBox(height: AppSpacing.x3),
                            TextFormField(
                              controller: _symptomsController,
                              maxLength: 3000,
                              maxLines: 3,
                              decoration: InputDecoration(
                                labelText: _t('symptomsDetails'),
                                border: const OutlineInputBorder(),
                                counterText: '',
                              ),
                            ),
                            if (widget.bodyLocation.trim().isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.x2),
                              Text(
                                '${_t('bodyLocation')}: ${widget.bodyLocation}',
                              ),
                            ],
                          ],
                        ),
                      ),
                    if (_step == 1)
                      _card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _sectionTitle(
                              _t('medicationAnalysis'),
                              Icons.medication_outlined,
                            ),
                            _triQuestion(
                              title: _t('medicationQuestion'),
                              value: _medicationStatus,
                              onChanged: (value) => setState(() {
                                _medicationStatus = value;
                                if (value != 'yes') {
                                  _medicationPrescribed = null;
                                  _medicationEffect = null;
                                  _medicationDurationController.clear();
                                  _medicationNameController.clear();
                                  _medicationImage = null;
                                  _medicationFilename = null;
                                }
                              }),
                            ),
                            if (_medicationStatus == 'yes') ...[
                              const SizedBox(height: AppSpacing.x2),
                              Text(_t('medicationRecognitionUnavailable')),
                              const SizedBox(height: AppSpacing.x3),
                              OutlinedButton.icon(
                                onPressed:
                                    _processing ? null : _chooseMedicationImage,
                                icon: const Icon(Icons.add_a_photo_outlined),
                                label: Text(
                                  _medicationFilename ?? _t('medicationPhoto'),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (_medicationImage != null)
                                Semantics(
                                  label: _t('medicationPhoto'),
                                  child: ClipRRect(
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.medium),
                                    child: Image.memory(
                                      _medicationImage!,
                                      height: 150,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: AppSpacing.x3),
                              TextFormField(
                                controller: _medicationNameController,
                                maxLength: 200,
                                decoration: InputDecoration(
                                  labelText: _t('medicationName'),
                                  hintText: _t('medicationNameHint'),
                                  border: const OutlineInputBorder(),
                                  counterText: '',
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                              const SizedBox(height: AppSpacing.x3),
                              TextFormField(
                                controller: _medicationDurationController,
                                maxLength: 200,
                                decoration: InputDecoration(
                                  labelText: _t('medicationDuration'),
                                  border: const OutlineInputBorder(),
                                  counterText: '',
                                ),
                              ),
                              const SizedBox(height: AppSpacing.x3),
                              _dropdown(
                                label: _t('prescribedQuestion'),
                                value: _medicationPrescribed,
                                items: [
                                  _option('yes', _appT('yes')),
                                  _option('no', _appT('no')),
                                  _option('unsure', _t('unsure')),
                                ],
                                onChanged: (value) => setState(
                                  () => _medicationPrescribed = value,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.x3),
                              _dropdown(
                                label: _t('effectQuestion'),
                                value: _medicationEffect,
                                items: [
                                  _option('improved', _t('improved')),
                                  _option('worsened', _t('worsened')),
                                  _option('no_change', _t('noChange')),
                                  _option('unsure', _t('unsure')),
                                ],
                                onChanged: (value) =>
                                    setState(() => _medicationEffect = value),
                              ),
                            ],
                          ],
                        ),
                      ),
                    if (_step == 2)
                      _card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _sectionTitle(
                              _t('examinationInterpretation'),
                              Icons.description_outlined,
                            ),
                            _triQuestion(
                              title: _t('examinationQuestion'),
                              value: _examinationStatus,
                              onChanged: (value) => setState(() {
                                _examinationStatus = value;
                                if (value != 'yes') _reports.clear();
                              }),
                            ),
                            if (_examinationStatus == 'yes') ...[
                              const SizedBox(height: AppSpacing.x2),
                              Text(_t('reportHint')),
                              const SizedBox(height: AppSpacing.x2),
                              TextFormField(
                                controller: _examinationDateController,
                                maxLength: 100,
                                decoration: InputDecoration(
                                  labelText: _t('examinationDate'),
                                  border: const OutlineInputBorder(),
                                  counterText: '',
                                ),
                              ),
                              const SizedBox(height: AppSpacing.x3),
                              TextFormField(
                                controller: _examinationFindingsController,
                                maxLength: 3000,
                                maxLines: 3,
                                decoration: InputDecoration(
                                  labelText: _t('doctorFindings'),
                                  border: const OutlineInputBorder(),
                                  counterText: '',
                                ),
                              ),
                              const SizedBox(height: AppSpacing.x3),
                              TextFormField(
                                controller: _examinationDiagnosisController,
                                maxLength: 2000,
                                maxLines: 2,
                                decoration: InputDecoration(
                                  labelText: _t('documentedDiagnosis'),
                                  border: const OutlineInputBorder(),
                                  counterText: '',
                                ),
                              ),
                              const SizedBox(height: AppSpacing.x2),
                              Text(_t('medicalReportUnavailable')),
                              const SizedBox(height: AppSpacing.x2),
                              OutlinedButton.icon(
                                onPressed:
                                    _processing ? null : _chooseReportSource,
                                icon: const Icon(Icons.upload_file_outlined),
                                label: Text(_t('addReport')),
                              ),
                              for (var index = 0;
                                  index < _reports.length;
                                  index++)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    _reports[index].mimeType ==
                                            'application/pdf'
                                        ? Icons.picture_as_pdf_outlined
                                        : Icons.image_outlined,
                                  ),
                                  title: Text(
                                    _reports[index].filename,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: IconButton(
                                    tooltip: _t('removeAttachment'),
                                    onPressed: _processing
                                        ? null
                                        : () => setState(
                                              () => _reports.removeAt(index),
                                            ),
                                    icon: const Icon(Icons.close),
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    if (_step == 2)
                      _card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _storageConsent,
                              onChanged: _processing
                                  ? null
                                  : (value) => setState(
                                        () => _storageConsent = value ?? false,
                                      ),
                              title: Text(_t('storageConsent')),
                              subtitle: Text(_t('storageDescription')),
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                            Text(_t('processingConsentBody')),
                          ],
                        ),
                      ),
                    if (_error != null)
                      _card(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (_processing) ...[
                      LinearProgressIndicator(
                        value: _uploadProgress == 0 ? null : _uploadProgress,
                      ),
                      const SizedBox(height: AppSpacing.x2),
                      Text(_t('processing')),
                    ],
                    const SizedBox(height: AppSpacing.x4),
                  ],
                ),
              ),
            ),
          );
        },
      );

  Widget _detail(String label, String? value) {
    final displayed =
        value?.trim().isNotEmpty == true ? value!.trim() : _t('notProvided');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          const SizedBox(width: AppSpacing.x2),
          Expanded(child: SelectableText(displayed)),
        ],
      ),
    );
  }

  Widget _bulletList(List<String> values, {String? emptyMessage}) {
    final items = values.where((value) => value.trim().isNotEmpty).toList();
    if (items.isEmpty) {
      return Text(emptyMessage ?? _t('noneReported'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  '),
                Expanded(child: SelectableText(item)),
              ],
            ),
          ),
      ],
    );
  }

  String _shortPreview(String value) {
    final plainText = value
        .replaceAll(RegExp(r'[#*_`>]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (plainText.length <= 180) return plainText;
    return '${plainText.substring(0, 177).trimRight()}…';
  }

  Widget _buildSkinResult(MedicalAssessmentResult result) {
    final skin = result.skinAnalysis;
    final summary = skin['summary']?.toString() ?? _t('notProvided');
    final rawConfidence = skin['confidence'];
    final confidence = rawConfidence is num
        ? rawConfidence <= 1
            ? rawConfidence * 100
            : rawConfidence
        : null;
    final confidenceText = confidence == null
        ? null
        : '${confidence == confidence.roundToDouble() ? confidence.toStringAsFixed(0) : confidence.toStringAsFixed(1)}%';
    final concernKey = switch (result.safety.concernLevel) {
      'low' => 'concernLow',
      'moderate' => 'concernModerate',
      'high' => 'concernHigh',
      'prompt_in_person' => 'concernPrompt',
      'insufficient' => 'concernInsufficient',
      _ => 'concernModerate',
    };
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(_t('skinImageAnalysis'), Icons.auto_awesome_outlined),
          Text(_t('possiblePattern')),
          _detail(_t('screeningEstimate'), skin['result']?.toString()),
          _detail(_t('modelConfidence'), confidenceText),
          _detail(_t('concernLevel'), _t(concernKey)),
          Text(
            _shortPreview(summary),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          ExpansionTile(
            key: const ValueKey('assessment-skin-details'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Text(_t('scanCardShowMore')),
            children: [SelectableText(summary)],
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            _t('screeningLimitations'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildMedicationResult(MedicalAssessmentResult result) {
    final medication = result.medication;
    final history = result.medicationHistory;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(
            _t('medicationAnalysis'),
            Icons.medication_outlined,
          ),
          Container(
            padding: const EdgeInsets.all(AppSpacing.x3),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(AppRadius.medium),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: AppSpacing.x2),
                Expanded(
                  child: Text(
                    _t('medicationSafetyWarning'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.x3),
          if (medication == null)
            Text(_t('noMedicationReported'))
          else ...[
            _detail(_t('medicationName'), medication.name),
            _detail(
              _t('verificationStatus'),
              _t(medication.verified ? 'verified' : 'unverified'),
            ),
            ExpansionTile(
              key: const ValueKey('assessment-medication-details'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(_t('scanCardShowMore')),
              subtitle: medication.intendedUses.isEmpty
                  ? null
                  : Text(
                      _shortPreview(medication.intendedUses.first),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
              children: [
                _detail(
                  _t('activeIngredients'),
                  medication.ingredients.isEmpty
                      ? null
                      : medication.ingredients.join(', '),
                ),
                _detail(_t('medicationStrength'), medication.strength),
                _detail(_t('manufacturer'), medication.manufacturer),
                _detail(
                  _t('visibleInstructions'),
                  medication.visibleInstructions,
                ),
                _detail(_t('category'), medication.category),
                _detail(_t('referenceSource'), medication.source),
                if (medication.verified) Text(medication.verificationNote),
                const Divider(height: AppSpacing.x6),
                _sectionTitle(_t('potentialBenefits'), Icons.info_outline),
                _detail(_t('intendedUses'), medication.intendedUses.join('\n')),
                _detail(_t('howItWorks'), medication.howItWorks),
                const Divider(height: AppSpacing.x6),
                _sectionTitle(
                  _t('potentialRisks'),
                  Icons.warning_amber_outlined,
                ),
                _detail(
                  _t('commonSideEffects'),
                  medication.commonSideEffects.join('\n'),
                ),
                _detail(
                  _t('seriousWarnings'),
                  medication.seriousWarningSigns.join('\n'),
                ),
                _detail(
                  _t('contraindications'),
                  medication.contraindications.join('\n'),
                ),
                _detail(
                  _t('possibleInteractions'),
                  medication.interactions.join('\n'),
                ),
                _detail(_t('precautions'), medication.precautions.join('\n')),
                _detail(
                  _t('storageInstructions'),
                  medication.storageInstructions.join('\n'),
                ),
                const Divider(height: AppSpacing.x6),
                Text(result.guidance.medicationExplanation),
              ],
            ),
          ],
          if (history != null) ...[
            ExpansionTile(
              key: const ValueKey('assessment-medication-history'),
              tilePadding: EdgeInsets.zero,
              title: Text(_t('scanCardShowMore')),
              children: [
                _detail(
                  _t('medicationDuration'),
                  history['duration']?.toString(),
                ),
                _detail(
                  _t('prescribedQuestion'),
                  history['prescribed_by_doctor']?.toString(),
                ),
                _detail(
                  _t('effectQuestion'),
                  history['reported_effect']?.toString(),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.x2),
          Text(_t('screeningLimitations')),
        ],
      ),
    );
  }

  Widget _buildExaminationCard(
    MedicalAssessmentResult result,
    int index,
  ) {
    final examination = result.examinations[index];
    final preview = [
          ...examination.doctorFindings,
          ...examination.documentedDiagnosis,
          examination.examinationDate ?? '',
        ].where((value) => value.trim().isNotEmpty).firstOrNull ??
        _t('notProvided');

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(
            '${_t('examinationRecordDetails')} ${index + 1}',
            Icons.description_outlined,
          ),
          Text(
            _shortPreview(preview),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          ExpansionTile(
            key: ValueKey('assessment-report-details-$index'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Text(_t('scanCardShowMore')),
            children: [
              _detail(
                _t('recordSource'),
                _t(
                  examination.source == 'patient_reported'
                      ? 'sourcePatientReported'
                      : 'sourceUnavailable',
                ),
              ),
              _detail(_t('examinationDate'), examination.examinationDate),
              _detail(
                  _t('doctorFindings'), examination.doctorFindings.join('\n')),
              _detail(
                _t('documentedDiagnosis'),
                examination.documentedDiagnosis.join('\n'),
              ),
              if (index < _reports.length ||
                  result.originalFiles
                      .any((file) => file.kind == 'medical_report_$index'))
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton.icon(
                    onPressed: () => _openOriginalReport(result, index),
                    icon: const Icon(Icons.open_in_new),
                    label: Text(_t('viewOriginal')),
                  ),
                ),
              for (final test in examination.tests) ...[
                _detail(_t('testName'), test.testName),
                _detail(_t('testDate'), test.date),
                _detail(_t('testResult'), test.result),
                _detail(_t('referenceRange'), test.referenceRange),
                if (test.explicitlyFlaggedAbnormal == true)
                  Chip(label: Text(_t('markedAbnormal'))),
                const Divider(),
              ],
              _detail(_t('conclusions'), examination.conclusions.join('\n')),
              _detail(
                _t('recommendedTreatments'),
                examination.recommendedTreatments.join('\n'),
              ),
              _detail(_t('medicationNames'),
                  examination.medicationNames.join('\n')),
              _detail(
                _t('followUpInstructions'),
                examination.followUpInstructions.join('\n'),
              ),
              _detail(_t('otherReportText'),
                  examination.otherReportText.join('\n')),
              _detail(_t('uncertainty'), examination.uncertainty.join('\n')),
              _detail(
                _t('missingInformation'),
                examination.missingOrUnreadable.join('\n'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMedicalReportResult(MedicalAssessmentResult result) {
    if (result.examinations.isEmpty) {
      return _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(
              _t('examinationInterpretation'),
              Icons.description_outlined,
            ),
            Text(_t('noReportsProvided')),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (var index = 0; index < result.examinations.length; index++)
          _buildExaminationCard(result, index),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionTitle(
                _t('assessmentSummary'),
                Icons.auto_awesome_outlined,
              ),
              Text(
                _shortPreview(result.guidance.examinationExplanation),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              ExpansionTile(
                key: const ValueKey('assessment-report-explanation'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(_t('scanCardShowMore')),
                children: [
                  SelectableText(result.guidance.examinationExplanation),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openOriginalReport(
    MedicalAssessmentResult result,
    int index,
  ) async {
    try {
      final kind = 'medical_report_$index';
      final stored =
          result.originalFiles.where((file) => file.kind == kind).firstOrNull;
      final inMemory = index < _reports.length ? _reports[index] : null;
      if (stored == null && inMemory == null) {
        throw const MedicalAssessmentApiException(
          'The original medical report is unavailable.',
        );
      }
      final bytes = stored != null
          ? await _api.originalFile(assessmentId: result.id, fileId: stored.id)
          : inMemory!.bytes;
      if (!mounted) return;
      final mimeType = stored?.mimeType ?? inMemory!.mimeType;
      final filename = inMemory?.filename ?? 'medical-report';
      if (mimeType == 'application/pdf') {
        await Printing.layoutPdf(
          name: filename,
          onLayout: (_) async => bytes,
        );
      } else {
        await showDialog<void>(
          context: context,
          builder: (context) => Dialog(
            child: InteractiveViewer(
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          ),
        );
      }
    } on Exception {
      if (mounted) _notice(_t('uploadError'));
    }
  }

  Widget _buildGuidance(MedicalAssessmentResult result) {
    final guidance = result.guidance;
    return Column(
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionTitle(
                _t('concerningFindings'),
                Icons.info_outline,
              ),
              Text(
                _shortPreview(
                  guidance.concerningObservations.firstOrNull ??
                      guidance.reassuringObservations.firstOrNull ??
                      _t('notProvided'),
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              ExpansionTile(
                key: const ValueKey('assessment-findings-details'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(_t('scanCardShowMore')),
                children: [
                  _sectionTitle(
                    _t('reassuringFindings'),
                    Icons.check_circle_outline,
                  ),
                  _bulletList(guidance.reassuringObservations),
                  _sectionTitle(
                    _t('concerningFindings'),
                    Icons.info_outline,
                  ),
                  _bulletList(guidance.concerningObservations),
                  _sectionTitle(
                    _t('missingInformation'),
                    Icons.help_outline,
                  ),
                  _bulletList(guidance.missingInformation),
                ],
              ),
            ],
          ),
        ),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionTitle(
                _t('recommendations'),
                Icons.lightbulb_outline,
              ),
              if (guidance.recommendations.isNotEmpty)
                Text(
                  _shortPreview(guidance.recommendations.join(' ')),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ExpansionTile(
                key: const ValueKey('assessment-recommendations-details'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(_t('scanCardShowMore')),
                children: [_bulletList(guidance.recommendations)],
              ),
              _detail(_t('clinicianFollowUp'), guidance.clinicianFollowUp),
              _detail(_t('urgentCare'), guidance.urgentCareGuidance),
            ],
          ),
        ),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionTitle(
                _t('medicalDisclaimer'),
                Icons.health_and_safety_outlined,
              ),
              Text(guidance.disclaimer),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReferralCard(MedicalAssessmentResult result) => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionTitle(
              _t('urgentDermatologistReferral'),
              Icons.health_and_safety_outlined,
            ),
            Text(result.guidance.clinicianFollowUp),
            const SizedBox(height: AppSpacing.x3),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DoctorDirectoryScreen(
                    baseUrl: widget.baseUrl,
                    idTokenProvider: () =>
                        widget.tokenProvider(forceRefresh: false),
                  ),
                ),
              ),
              icon: const Icon(Icons.search),
              label: Text(_t('findDermatologist')),
            ),
          ],
        ),
      );

  Future<void> _exportPdf(MedicalAssessmentResult result) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final bytes = await buildMedicalAssessmentPdf(
        assessment: result,
        localize: _t,
        isRtl: Directionality.of(context) == TextDirection.rtl,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'skinai_medical_assessment_${result.createdAt.year}.pdf',
      );
    } on Exception {
      if (mounted) _notice(_t('reportExportFailed'));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _buildResult(MedicalAssessmentResult result) => LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth =
              constraints.maxWidth > 900 ? 900.0 : constraints.maxWidth;
          return Center(
            child: SizedBox(
              width: maxWidth,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.x4),
                children: [
                  Text(
                    _t('resultTitle'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionTitle(
                          _t('patientInformation'),
                          Icons.person_outline,
                        ),
                        _detail(_t('patientAge'), '${result.patient.age}'),
                        _detail(
                          _t('patientSex'),
                          _t(result.patient.sex == 'prefer_not_to_say'
                              ? 'preferNot'
                              : result.patient.sex),
                        ),
                        ExpansionTile(
                          key: const ValueKey('assessment-patient-details'),
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: EdgeInsets.zero,
                          title: Text(_t('scanCardShowMore')),
                          children: [
                            _detail(
                              _t('symptomsDuration'),
                              result.patient.symptomsDuration,
                            ),
                            _detail(
                              _t('symptomsDetails'),
                              result.patient.symptomsDetails,
                            ),
                            _detail(
                              _t('bodyLocation'),
                              result.patient.bodyLocation,
                            ),
                            _detail(
                              _t('pregnancy'),
                              _t('pregnancy_${result.patient.pregnancyOrBreastfeeding}'),
                            ),
                            _detail(
                              _t('allergies'),
                              result.patient.allergies,
                            ),
                            _detail(
                              _t('medicalHistory'),
                              result.patient.medicalHistory,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _buildSkinResult(result),
                  if (result.safety.referralRequired)
                    _buildReferralCard(result),
                  _buildMedicationResult(result),
                  _buildMedicalReportResult(result),
                  _buildGuidance(result),
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionTitle(
                            _t('reportSources'), Icons.source_outlined),
                        if (result.sources.isNotEmpty)
                          Text(
                            _shortPreview(result.sources.join(', ')),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ExpansionTile(
                          key: const ValueKey('assessment-sources-details'),
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: EdgeInsets.zero,
                          title: Text(_t('scanCardShowMore')),
                          children: [_bulletList(result.sources)],
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _exporting ? null : () => _exportPdf(result),
                    icon: _exporting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(
                      _exporting ? _appT('reportGenerating') : _t('exportPdf'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x4),
                ],
              ),
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(
        title: Text(_t(result == null ? 'title' : 'resultTitle')),
        leading: Navigator.of(context).canPop()
            ? IconButton(
                tooltip: _appT('back'),
                onPressed: _goBackOrClose,
                icon: const Icon(Icons.arrow_back),
              )
            : null,
        actions: [
          if (result != null)
            IconButton(
              tooltip: _t('exportPdf'),
              onPressed: _exporting ? null : () => _exportPdf(result),
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: result == null ? _buildForm() : _buildResult(result),
      ),
      bottomNavigationBar: result == null
          ? SafeArea(
              minimum: const EdgeInsets.all(AppSpacing.x4),
              child: FilledButton.icon(
                onPressed:
                    _processing ? null : (_step < 2 ? _continue : _submit),
                icon: _processing
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _step < 2
                            ? Icons.arrow_forward_rounded
                            : Icons.health_and_safety_outlined,
                      ),
                label: Text(
                  _processing
                      ? _t('processing')
                      : _step < 2
                          ? _t('nextStep')
                          : _t('startAssessment'),
                ),
              ),
            )
          : null,
    );
  }
}
