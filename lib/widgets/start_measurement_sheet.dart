import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:blu/models/survey.dart';

class StartMeasurementResult {
  final String measurementName;
  final int? existingSurveyId;
  final String? newSurveyName;
  final int expectedJoints;
  final int expectedPhotos;
  final int expectedVideos;

  const StartMeasurementResult({
    required this.measurementName,
    this.existingSurveyId,
    this.newSurveyName,
    required this.expectedJoints,
    required this.expectedPhotos,
    required this.expectedVideos,
  });
}

class StartMeasurementSheet extends StatefulWidget {
  final List<Survey> surveys;

  const StartMeasurementSheet({super.key, required this.surveys});

  @override
  State<StartMeasurementSheet> createState() => _StartMeasurementSheetState();
}

class _StartMeasurementSheetState extends State<StartMeasurementSheet> {
  final _nameCtrl = TextEditingController();
  final _surveyNameCtrl = TextEditingController();
  final _jointsCtrl = TextEditingController();
  final _photosCtrl = TextEditingController();
  final _videosCtrl = TextEditingController();

  String _mode = 'existing';
  Survey? _selectedSurvey;
  String? _nameError;
  String? _surveyError;
  String? _jointsError;
  String? _photosError;
  String? _videosError;

  @override
  void initState() {
    super.initState();
    if (widget.surveys.isEmpty) {
      _mode = 'new';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _surveyNameCtrl.dispose();
    _jointsCtrl.dispose();
    _photosCtrl.dispose();
    _videosCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1C1C1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Scrollable body
            Flexible(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Start Recording',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildField(
                      ctrl: _nameCtrl,
                      label: 'Measurement name *',
                      error: _nameError,
                      onChanged: (_) => setState(() => _nameError = null),
                    ),
                    const SizedBox(height: 20),
                    _sectionLabel('Survey'),
                    const SizedBox(height: 10),
                    _buildSurveyToggle(),
                    const SizedBox(height: 12),
                    _buildSurveyInput(),
                    const SizedBox(height: 20),
                    _sectionLabel('Expected Workload'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildField(
                            ctrl: _jointsCtrl,
                            label: 'Joints (optional)',
                            error: _jointsError,
                            keyboard: TextInputType.number,
                            formatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            onChanged: (_) =>
                                setState(() => _jointsError = null),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildField(
                            ctrl: _photosCtrl,
                            label: 'Photos (optional)',
                            error: _photosError,
                            keyboard: TextInputType.number,
                            formatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            onChanged: (_) =>
                                setState(() => _photosError = null),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildField(
                            ctrl: _videosCtrl,
                            label: 'Videos (optional)',
                            error: _videosError,
                            keyboard: TextInputType.number,
                            formatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            onChanged: (_) =>
                                setState(() => _videosError = null),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            // Pinned footer
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController ctrl,
    required String label,
    String? error,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    required void Function(String) onChanged,
  }) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white),
      keyboardType: keyboard ?? TextInputType.text,
      inputFormatters: formatters ?? [],
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
        floatingLabelStyle: const TextStyle(
          color: Color(0xFF7d0d0d),
          fontSize: 12,
        ),
        filled: true,
        fillColor: const Color(0xFF2C2C2E),
        errorText: error,
        errorStyle: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 11),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF7d0d0d), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFF6B6B), width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFF6B6B), width: 1.5),
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildSurveyToggle() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => setState(() {
              _mode = 'existing';
              _surveyError = null;
            }),
            style: OutlinedButton.styleFrom(
              backgroundColor: _mode == 'existing'
                  ? const Color(0xFF7d0d0d)
                  : Colors.transparent,
              foregroundColor:
                  _mode == 'existing' ? Colors.white : Colors.white54,
              side: BorderSide(
                color: _mode == 'existing'
                    ? const Color(0xFF7d0d0d)
                    : Colors.white30,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              minimumSize: const Size(double.infinity, 42),
              padding: EdgeInsets.zero,
            ),
            child: const Text('Existing Survey'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: () => setState(() {
              _mode = 'new';
              _surveyError = null;
            }),
            style: OutlinedButton.styleFrom(
              backgroundColor:
                  _mode == 'new' ? const Color(0xFF7d0d0d) : Colors.transparent,
              foregroundColor: _mode == 'new' ? Colors.white : Colors.white54,
              side: BorderSide(
                color:
                    _mode == 'new' ? const Color(0xFF7d0d0d) : Colors.white30,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              minimumSize: const Size(double.infinity, 42),
              padding: EdgeInsets.zero,
            ),
            child: const Text('New Survey'),
          ),
        ),
      ],
    );
  }

  Widget _buildSurveyInput() {
    if (_mode == 'existing' && widget.surveys.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'No existing surveys — switch to "New Survey".',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
      );
    }

    if (_mode == 'existing' && widget.surveys.isNotEmpty) {
      return DropdownButtonFormField<Survey>(
        value: _selectedSurvey,
        dropdownColor: const Color(0xFF2C2C2E),
        style: const TextStyle(color: Colors.white),
        iconEnabledColor: Colors.white54,
        decoration: InputDecoration(
          filled: true,
          fillColor: const Color(0xFF2C2C2E),
          errorText: _surveyError,
          errorStyle: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 11),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF7d0d0d), width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFFF6B6B), width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFFF6B6B), width: 1.5),
          ),
        ),
        hint: const Text(
          'Select survey',
          style: TextStyle(color: Colors.white54),
        ),
        items: widget.surveys
            .map((s) => DropdownMenuItem(value: s, child: Text(s.name)))
            .toList(),
        onChanged: (v) => setState(() {
          _selectedSurvey = v;
          _surveyError = null;
        }),
      );
    }

    // _mode == 'new'
    return _buildField(
      ctrl: _surveyNameCtrl,
      label: 'New survey name *',
      error: _surveyError,
      onChanged: (_) => setState(() => _surveyError = null),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      color: const Color(0xFF1C1C1E),
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        MediaQuery.of(context).viewInsets.bottom > 0
            ? 12
            : MediaQuery.of(context).padding.bottom + 16,
      ),
      child: FilledButton.icon(
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text(
          'Start Recording',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        onPressed: _onSubmit,
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          backgroundColor: const Color(0xFF7d0d0d),
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  void _onSubmit() {
    final name = _nameCtrl.text.trim();
    final surveyName = _surveyNameCtrl.text.trim();
    final joints = int.tryParse(_jointsCtrl.text.trim()) ?? 0;
    final photos = int.tryParse(_photosCtrl.text.trim()) ?? 0;
    final videos = int.tryParse(_videosCtrl.text.trim()) ?? 0;

    bool hasError = false;
    if (name.isEmpty) {
      _nameError = 'Required';
      hasError = true;
    }
    if (_mode == 'existing' &&
        (widget.surveys.isEmpty || _selectedSurvey == null)) {
      _surveyError = 'Select a survey';
      hasError = true;
    }
    if (_mode == 'new' && surveyName.isEmpty) {
      _surveyError = 'Required';
      hasError = true;
    }

    if (hasError) {
      setState(() {});
      return;
    }

    Navigator.pop(
      context,
      StartMeasurementResult(
        measurementName: name,
        existingSurveyId: _mode == 'existing' ? _selectedSurvey!.id : null,
        newSurveyName: _mode == 'new' ? surveyName : null,
        expectedJoints: joints,
        expectedPhotos: photos,
        expectedVideos: videos,
      ),
    );
  }
}
