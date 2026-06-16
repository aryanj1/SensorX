import 'package:flutter/material.dart';

import 'package:blu/app.dart';
import 'package:blu/models/survey.dart';
import 'package:blu/models/surveyor.dart';
import 'package:blu/services/cache_service.dart';
import 'package:blu/services/database_service.dart';
import 'package:blu/screens/survey/survey_screen.dart';

/// Lists all surveys belonging to [surveyor] and lets the user create or delete them.
class SurveyorScreen extends StatefulWidget {
  final Surveyor surveyor;
  final TTLFileCache? cache;

  const SurveyorScreen({super.key, required this.surveyor, this.cache});

  @override
  State<SurveyorScreen> createState() => _SurveyorScreenState();
}

class _SurveyorScreenState extends State<SurveyorScreen> {
  List<Survey> _surveys = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSurveys();
  }

  Future<void> _loadSurveys() async {
    final db = await DatabaseService.instance();
    final results = await db.getSurveysForSurveyor(widget.surveyor.id!);
    if (!mounted) return;
    setState(() {
      _surveys = results;
      _loading = false;
    });
  }

  // ---------------------------------------------------------------------------
  // New survey dialog
  // ---------------------------------------------------------------------------

  Future<void> _showNewSurveyDialog() async {
    final nameController = TextEditingController();
    String? nameError;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('New Survey'),
              content: TextField(
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Survey name *',
                  errorText: nameError,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      setDialogState(() => nameError = 'Name is required');
                      return;
                    }
                    final db = await DatabaseService.instance();
                    await db.insertSurvey(
                      Survey(
                        name: name,
                        surveyorName: widget.surveyor.name,
                        surveyorId: widget.surveyor.id,
                        createdAt: DateTime.now().toUtc().toIso8601String(),
                      ),
                    );
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    await _loadSurveys();
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Delete survey confirmation
  // ---------------------------------------------------------------------------

  Future<void> _confirmDeleteSurvey(Survey s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Survey'),
        content: Text(
          "Delete '${s.name}'? All measurements and readings will be deleted.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final db = await DatabaseService.instance();
    await db.deleteSurvey(s.id!);
    await _loadSurveys();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: sensorXRed,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.surveyor.name),
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _showNewSurveyDialog,
        tooltip: 'New survey',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_surveys.isEmpty) {
      return const Center(child: Text('No surveys yet. Tap + to add one.'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Surveys',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _surveys.length,
            itemBuilder: (context, index) {
              final survey = _surveys[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ListTile(
                  title: Text(survey.name),
                  subtitle: Text(survey.createdAt),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.chevron_right),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Delete survey',
                        onPressed: () => _confirmDeleteSurvey(survey),
                      ),
                    ],
                  ),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SurveyScreen(
                          survey: _surveys[index],
                          cache: widget.cache,
                        ),
                      ),
                    );
                    await _loadSurveys();
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
