import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class StocktakeLocalNotes {
  const StocktakeLocalNotes({required this.comments, required this.rechecked});

  final Map<int, String> comments;
  final Set<int> rechecked;
}

class StocktakeNoteStore {
  Future<File> _file(int draftId) async {
    final dir = await getApplicationSupportDirectory();
    final folder = Directory(p.join(dir.path, 'stocktake_drafts'));
    if (!await folder.exists()) await folder.create(recursive: true);
    return File(p.join(folder.path, 'draft_${draftId}_notes.json'));
  }

  Future<StocktakeLocalNotes> load(int draftId) async {
    try {
      final file = await _file(draftId);
      if (!await file.exists()) return const StocktakeLocalNotes(comments: {}, rechecked: {});
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return const StocktakeLocalNotes(comments: {}, rechecked: {});
      final rawComments = decoded['comments'];
      final comments = <int, String>{};
      if (rawComments is Map) {
        for (final entry in rawComments.entries) {
          final id = int.tryParse('${entry.key}');
          final value = '${entry.value ?? ''}';
          if (id != null && value.trim().isNotEmpty) comments[id] = value;
        }
      }
      final rechecked = <int>{};
      final rawRechecked = decoded['rechecked'];
      if (rawRechecked is List) {
        for (final value in rawRechecked) {
          final id = value is int ? value : int.tryParse('$value');
          if (id != null) rechecked.add(id);
        }
      }
      return StocktakeLocalNotes(comments: comments, rechecked: rechecked);
    } catch (_) {
      return const StocktakeLocalNotes(comments: {}, rechecked: {});
    }
  }

  Future<void> save(int draftId, {required Map<int, String> comments, required Set<int> rechecked}) async {
    final file = await _file(draftId);
    await file.writeAsString(
      jsonEncode({
        'comments': {for (final entry in comments.entries) '${entry.key}': entry.value},
        'rechecked': rechecked.toList(growable: false),
        'updated_at': DateTime.now().toIso8601String(),
      }),
      flush: true,
    );
  }

  Future<void> clear(int draftId) async {
    try {
      final file = await _file(draftId);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best effort cleanup. The draft ID will not be reused by SQLite.
    }
  }
}
