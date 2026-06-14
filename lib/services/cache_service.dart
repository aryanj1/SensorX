import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class FileCacheEntry {
  final String filename;
  final DateTime expiresAt;
  final int bytes;
  final String mime;
  final Map<String, dynamic>? meta;

  FileCacheEntry({
    required this.filename,
    required this.expiresAt,
    required this.bytes,
    required this.mime,
    this.meta,
  });

  Map<String, dynamic> toJson() => {
        'filename': filename,
        'expiresAt': expiresAt.toIso8601String(),
        'bytes': bytes,
        'mime': mime,
        'meta': meta,
      };

  static FileCacheEntry fromJson(Map<String, dynamic> j) => FileCacheEntry(
        filename: j['filename'] as String,
        expiresAt: DateTime.parse(j['expiresAt'] as String),
        bytes: j['bytes'] as int,
        mime: j['mime'] as String,
        meta: (j['meta'] as Map?)?.cast<String, dynamic>(),
      );
}

class TTLFileCache {
  TTLFileCache._();

  static const _folder = 'surveyor_cache';
  static const _indexName = '.index.json';
  static const _sessionCounterName = '.session_counter';

  late final Directory _dir;
  late final File _indexFile;
  late final File _sessionCounterFile;
  final Map<String, FileCacheEntry> _index = {};

  static Future<TTLFileCache> open() async {
    final cache = TTLFileCache._();
    final base = await getApplicationSupportDirectory(); // private per-app dir
    cache._dir = Directory('${base.path}/$_folder');
    if (!(await cache._dir.exists())) {
      await cache._dir.create(recursive: true);
    }
    cache._indexFile = File('${cache._dir.path}/$_indexName');
    cache._sessionCounterFile = File('${cache._dir.path}/$_sessionCounterName');
    await cache._loadIndex();
    await cache._initSessionCounterIfNeeded();
    await cache.purgeExpired();
    return cache;
  }

  Future<void> _initSessionCounterIfNeeded() async {
    if (!await _sessionCounterFile.exists()) {
      await _sessionCounterFile.writeAsString('0');
    }
  }

  Future<int> nextSessionNumber() async {
    try {
      int current = 0;
      if (await _sessionCounterFile.exists()) {
        final raw = (await _sessionCounterFile.readAsString()).trim();
        current = int.tryParse(raw) ?? 0;
      }
      final next = current + 1;
      await _sessionCounterFile.writeAsString(next.toString(), flush: true);
      return next;
    } catch (_) {
      await _sessionCounterFile.writeAsString('1', flush: true);
      return 1;
    }
  }

  Future<void> _loadIndex() async {
    if (await _indexFile.exists()) {
      try {
        final raw = await _indexFile.readAsString();
        final list =
            (jsonDecode(raw) as List).cast<Map>().cast<Map<String, dynamic>>();
        _index
          ..clear()
          ..addEntries(
            list.map((m) {
              final e = FileCacheEntry.fromJson(m);
              return MapEntry(e.filename, e);
            }),
          );
      } catch (_) {
        await _rebuildIndexFromDisk();
      }
    } else {
      await _rebuildIndexFromDisk();
    }
  }

  Future<void> _rebuildIndexFromDisk() async {
    _index.clear();
    final files = _dir.listSync().whereType<File>().where((f) {
      final name = f.path.split('/').last;
      return name != _indexName && name != _sessionCounterName;
    });
    for (final f in files) {
      final stat = await f.stat();
      final name = f.path.split('/').last;
      _index[name] = FileCacheEntry(
        filename: name,
        expiresAt: DateTime.now().add(const Duration(days: 14)), // default TTL
        bytes: stat.size,
        mime: 'text/csv',
        meta: {'recovered': true},
      );
    }
    await _saveIndex();
  }

  Future<void> _saveIndex() async {
    final list = _index.values.map((e) => e.toJson()).toList(growable: false);
    await _indexFile.writeAsString(jsonEncode(list));
  }

  String _safe(String name) => name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  Future<void> ensureHeader({
    required String basename,
    required String headerLine,
    required Duration ttl,
    String mime = 'text/csv',
    Map<String, dynamic>? meta,
  }) async {
    final name = _safe(basename);
    final path = '${_dir.path}/$name';
    final f = File(path);
    final exists = await f.exists();
    if (!exists || (await f.length()) == 0) {
      final sink = f.openWrite(mode: FileMode.write);
      sink.writeln(headerLine);
      await sink.flush();
      await sink.close();
      final stat = await f.stat();
      _index[name] = FileCacheEntry(
        filename: name,
        expiresAt: DateTime.now().add(ttl),
        bytes: stat.size,
        mime: mime,
        meta: meta,
      );
      await _saveIndex();
    }
  }

  Future<String> appendLine({
    required String basename,
    required String line,
    required Duration ttl,
    String mime = 'text/csv',
    Map<String, dynamic>? meta,
  }) async {
    final name = _safe(basename);
    final path = '${_dir.path}/$name';
    final f = File(path);
    final sink = f.openWrite(mode: FileMode.append);
    sink.writeln(line);
    await sink.flush();
    await sink.close();
    final stat = await f.stat();
    _index[name] = FileCacheEntry(
      filename: name,
      expiresAt: _index[name]?.expiresAt ?? DateTime.now().add(ttl),
      bytes: stat.size,
      mime: mime,
      meta: meta ?? _index[name]?.meta,
    );
    await _saveIndex();
    return path;
  }

  Future<List<File>> listActive() async {
    final now = DateTime.now();
    final actives = _index.values.where((e) => e.expiresAt.isAfter(now));
    return actives.map((e) => File('${_dir.path}/${e.filename}')).toList();
  }

  Future<void> markUploaded(String filename) async {
    final name = _safe(filename);
    final f = File('${_dir.path}/$name');
    if (await f.exists()) {
      await f.delete();
    }
    _index.remove(name);
    await _saveIndex();
  }

  Future<int> purgeExpired() async {
    int removed = 0;
    final now = DateTime.now();
    final expired =
        _index.values.where((e) => e.expiresAt.isBefore(now)).toList();
    for (final e in expired) {
      final f = File('${_dir.path}/${e.filename}');
      if (await f.exists()) await f.delete();
      _index.remove(e.filename);
      removed++;
    }
    if (removed > 0) await _saveIndex();
    return removed;
  }

  Future<void> enforceMaxBytes(int maxBytes) async {
    int total = _index.values.fold(0, (s, e) => s + e.bytes);
    if (total <= maxBytes) return;
    final sorted = _index.values.toList()
      ..sort((a, b) {
        final c = a.expiresAt.compareTo(b.expiresAt);
        return c != 0 ? c : a.filename.compareTo(b.filename);
      });
    for (final e in sorted) {
      if (total <= maxBytes) break;
      final f = File('${_dir.path}/${e.filename}');
      if (await f.exists()) await f.delete();
      _index.remove(e.filename);
      total -= e.bytes;
    }
    await _saveIndex();
  }
}
