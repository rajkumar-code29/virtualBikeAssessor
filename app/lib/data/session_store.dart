// Copyright (c) 2026 Raj Kumar G K. All rights reserved.
// Proprietary and confidential. See LICENSE in the project root.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// One logged assessment plus, once a tech has seen the bike, the confirmed
/// outcome. These confirmed records are the training data for tuning the
/// knowledge base (and, much later, a model).
class SessionRecord {
  final String id;
  final DateTime createdAt;
  final Map<String, dynamic> assessment;
  List<String> confirmedCauses;
  String techNotes;
  DateTime? reviewedAt;

  SessionRecord({
    required this.id,
    required this.createdAt,
    required this.assessment,
    this.confirmedCauses = const [],
    this.techNotes = '',
    this.reviewedAt,
  });

  bool get reviewed => reviewedAt != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'created_at': createdAt.toIso8601String(),
        'assessment': assessment,
        'tech_review': reviewed
            ? {
                'confirmed_causes': confirmedCauses,
                'notes': techNotes,
                'reviewed_at': reviewedAt!.toIso8601String(),
              }
            : null,
      };

  factory SessionRecord.fromJson(Map<String, dynamic> j) {
    final review = j['tech_review'] as Map<String, dynamic>?;
    return SessionRecord(
      id: j['id'],
      createdAt: DateTime.parse(j['created_at']),
      assessment: j['assessment'],
      confirmedCauses: List<String>.from(review?['confirmed_causes'] ?? const []),
      techNotes: review?['notes'] ?? '',
      reviewedAt: review == null ? null : DateTime.parse(review['reviewed_at']),
    );
  }
}

/// Stores sessions as JSON files on the device. Swap for a backend table
/// (e.g. Supabase `assessments`) once there is more than one device.
class SessionStore {
  final List<SessionRecord> _memory = [];

  Future<Directory?> _dir() async {
    if (kIsWeb) return null;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/assessments');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> save(SessionRecord r) async {
    final dir = await _dir();
    if (dir == null) {
      _memory.removeWhere((m) => m.id == r.id);
      _memory.add(r);
      return;
    }
    await File('${dir.path}/${r.id}.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(r.toJson()));
  }

  Future<List<SessionRecord>> list() async {
    final dir = await _dir();
    final records = dir == null
        ? List.of(_memory)
        : [
            for (final f in dir.listSync().whereType<File>())
              if (f.path.endsWith('.json'))
                SessionRecord.fromJson(jsonDecode(await f.readAsString()))
          ];
    records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return records;
  }

  /// All sessions as one JSON document, for export to analysis.
  Future<String> exportAll() async => const JsonEncoder.withIndent('  ')
      .convert([for (final r in await list()) r.toJson()]);
}
