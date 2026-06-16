import 'dart:io';

import 'package:flutter/material.dart';

import 'package:blu/app.dart';
import '../files/csv_preview_screen.dart';
import '../../services/cache_service.dart';

class PendingFilesScreen extends StatefulWidget {
  final TTLFileCache cache;

  const PendingFilesScreen({super.key, required this.cache});

  @override
  State<PendingFilesScreen> createState() => _PendingFilesScreenState();
}

class _PendingFilesScreenState extends State<PendingFilesScreen> {
  late Future<List<_FileMeta>> _futureFiles;
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _futureFiles = _loadFiles();
      _err = null;
    });
  }

  Future<List<_FileMeta>> _loadFiles() async {
    final files = await widget.cache.listActive();
    files.sort((a, b) => a.path.compareTo(b.path));
    final metas = <_FileMeta>[];
    for (final f in files) {
      try {
        final stat = await f.stat();
        final lines = await _countLinesQuick(f, maxToRead: 1000000);
        metas.add(
          _FileMeta(
            name: f.uri.pathSegments.last,
            file: f,
            sizeBytes: stat.size,
            modified: stat.modified,
            recordCount: lines > 0 ? lines - 1 : 0, // minus header
          ),
        );
      } catch (e) {
        metas.add(
          _FileMeta(
            name: f.uri.pathSegments.last,
            file: f,
            sizeBytes: 0,
            modified: DateTime.fromMillisecondsSinceEpoch(0),
            recordCount: 0,
            error: e.toString(),
          ),
        );
      }
    }
    return metas;
  }

  static Future<int> _countLinesQuick(File f, {int maxToRead = 1000000}) async {
    final reader = f.openRead();
    int count = 0;
    await for (final chunk in reader) {
      for (final byte in chunk) {
        if (byte == 10) count++; // '\n'
        if (count >= maxToRead) break;
      }
      if (count >= maxToRead) break;
    }
    return count;
  }

  static Future<List<List<String>>> _readCsvPreview(
    String path, {
    int maxLines = 300,
  }) async {
    final lines = await File(path).readAsLines();
    final take = lines.take(maxLines).toList();
    return take.map((l) => l.split(',')).toList();
  }

  Future<void> _deleteLocal(String name) async {
    setState(() => _busy = true);
    try {
      await widget.cache.markUploaded(name);
    } finally {
      setState(() => _busy = false);
      _reload();
    }
  }

  Future<void> _purgeExpired() async {
    setState(() => _busy = true);
    try {
      await widget.cache.purgeExpired();
    } finally {
      setState(() => _busy = false);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: sensorXRed,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Pending Files'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Purge expired',
            onPressed: _busy ? null : _purgeExpired,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _busy ? null : _reload,
          ),
        ],
      ),
      body: FutureBuilder<List<_FileMeta>>(
        future: _futureFiles,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final items = snap.data ?? const [];
          final totalBytes = items.fold<int>(0, (s, m) => s + m.sizeBytes);

          return Column(
            children: [
              if (_err != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.red.withValues(alpha: 0.08),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline),
                      const SizedBox(width: 8),
                      Expanded(child: Text('Error: $_err')),
                    ],
                  ),
                ),
              _SummaryBar(count: items.length, bytes: totalBytes),
              const Divider(height: 0),
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('No pending files'))
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 0),
                        itemBuilder: (context, i) {
                          final m = items[i];
                          return ListTile(
                            leading: const CircleAvatar(
                              radius: 10,
                              child: Icon(Icons.insert_drive_file, size: 14),
                            ),
                            title: Text(
                              m.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              'Records: ${m.recordCount} • ${_fmtBytes(m.sizeBytes)} • Modified: ${m.modified.toLocal()}',
                            ),
                            trailing: Wrap(
                              spacing: 8,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.visibility),
                                  tooltip: 'Preview',
                                  onPressed: _busy
                                      ? null
                                      : () async {
                                          final rows = await _readCsvPreview(
                                            m.file.path,
                                            maxLines: 500,
                                          );
                                          if (!context.mounted) return;
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => CsvPreviewScreen(
                                                filename: m.name,
                                                rows: rows,
                                              ),
                                            ),
                                          );
                                        },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: 'Delete local',
                                  onPressed:
                                      _busy ? null : () => _deleteLocal(m.name),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              if (_busy) const LinearProgressIndicator(minHeight: 2),
            ],
          );
        },
      ),
    );
  }

  static String _fmtBytes(int n) {
    const kb = 1024, mb = 1024 * kb, gb = 1024 * mb;
    if (n >= gb) return '${(n / gb).toStringAsFixed(2)} GB';
    if (n >= mb) return '${(n / mb).toStringAsFixed(2)} MB';
    if (n >= kb) return '${(n / kb).toStringAsFixed(2)} KB';
    return '$n B';
  }
}

class _FileMeta {
  final String name;
  final File file;
  final int sizeBytes;
  final DateTime modified;
  final int recordCount;
  final String? error;

  _FileMeta({
    required this.name,
    required this.file,
    required this.sizeBytes,
    required this.modified,
    required this.recordCount,
    this.error,
  });
}

class _SummaryBar extends StatelessWidget {
  final int count;
  final int bytes;

  const _SummaryBar({required this.count, required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.folder,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text('Pending: $count • ${_fmtBytes(bytes)}'),
        ],
      ),
    );
  }

  static String _fmtBytes(int n) {
    const kb = 1024, mb = 1024 * kb, gb = 1024 * mb;
    if (n >= gb) return '${(n / gb).toStringAsFixed(2)} GB';
    if (n >= mb) return '${(n / mb).toStringAsFixed(2)} MB';
    if (n >= kb) return '${(n / kb).toStringAsFixed(2)} KB';
    return '$n B';
  }
}
