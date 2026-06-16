import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class WorkloadResult {
  final int joints;
  final int photos;
  final int videos;

  const WorkloadResult({
    required this.joints,
    required this.photos,
    required this.videos,
  });
}

class WorkloadSheet extends StatefulWidget {
  const WorkloadSheet({super.key});

  @override
  State<WorkloadSheet> createState() => _WorkloadSheetState();
}

class _WorkloadSheetState extends State<WorkloadSheet> {
  final _jointsCtrl = TextEditingController();
  final _photosCtrl = TextEditingController();
  final _videosCtrl = TextEditingController();

  String? _jointsError;
  String? _photosError;
  String? _videosError;

  @override
  void dispose() {
    _jointsCtrl.dispose();
    _photosCtrl.dispose();
    _videosCtrl.dispose();
    super.dispose();
  }

  bool _validateAndSubmit() {
    final j = int.tryParse(_jointsCtrl.text.trim());
    final p = int.tryParse(_photosCtrl.text.trim());
    final v = int.tryParse(_videosCtrl.text.trim());

    String? jointsErr;
    String? photosErr;
    String? videosErr;

    if (j == null || j <= 0) jointsErr = 'Enter a number greater than 0';
    if (p == null || p <= 0) photosErr = 'Enter a number greater than 0';
    if (v == null || v <= 0) videosErr = 'Enter a number greater than 0';

    if (jointsErr != null || photosErr != null || videosErr != null) {
      setState(() {
        _jointsError = jointsErr;
        _photosError = photosErr;
        _videosError = videosErr;
      });
      return false;
    }

    Navigator.pop(
      context,
      WorkloadResult(joints: j!, photos: p!, videos: v!),
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Workload',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Enter the expected workload for this measurement.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.white54),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _jointsCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Expected joints to survey',
                border: const OutlineInputBorder(),
                errorText: _jointsError,
              ),
              onChanged: (_) => setState(() => _jointsError = null),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _photosCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Expected photos',
                border: const OutlineInputBorder(),
                errorText: _photosError,
              ),
              onChanged: (_) => setState(() => _photosError = null),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _videosCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Expected videos',
                border: const OutlineInputBorder(),
                errorText: _videosError,
              ),
              onChanged: (_) => setState(() => _videosError = null),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text(
                'Start Recording',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: Colors.green.shade600,
                shape: const StadiumBorder(),
              ),
              onPressed: _validateAndSubmit,
            ),
          ],
        ),
      ),
    );
  }
}
