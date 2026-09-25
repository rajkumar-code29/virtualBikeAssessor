// Copyright (c) 2026 Raj Kumar G K. All rights reserved.
// Proprietary and confidential. See LICENSE in the project root.

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../engine/assessment_engine.dart';
import '../kb/knowledge_base.dart';

/// Translates free text and photos into values the engine understands.
/// The engine, not the AI, decides what to ask and what the result is.
abstract class AiService {
  String get name;

  /// Why the last AI call failed (the answer then came from the offline
  /// fallback), or null if it worked.
  String? get lastError;

  /// Maps a customer's description to a symptom id, or null if unclear.
  Future<String?> classifySymptom(String text, List<Symptom> symptoms);

  /// Maps a free-text reply to a check question onto ok / problem / unsure.
  Future<Answer> interpretAnswer(Check check, String text);

  /// Judges a photo against one check. Null when photo analysis isn't available.
  Future<PhotoAssessment?> assessPhoto(
      Check check, Uint8List bytes, String mediaType);
}

/// Offline fallback: phrase matching only, no photo analysis.
class LocalAiService implements AiService {
  @override
  String get name => 'Offline (keyword matching)';

  @override
  String? get lastError => null;

  @override
  Future<String?> classifySymptom(String text, List<Symptom> symptoms) async {
    final words = _words(text);
    String? best;
    var bestScore = 0.0;
    for (final s in symptoms) {
      for (final phrase in [...s.customerPhrases, s.label]) {
        final p = _words(phrase);
        if (p.isEmpty) continue;
        final score = p.intersection(words).length / p.length;
        if (score > bestScore) {
          bestScore = score;
          best = s.id;
        }
      }
    }
    return bestScore >= 0.5 ? best : null;
  }

  static const _okWords = {'fine', 'good', 'ok', 'okay', 'normal', 'perfect'};
  static const _problemWords = {
    'wrong', 'problem', 'broken', 'loose', 'worn', 'cracked', 'damaged',
    'noise', 'noisy', 'wobble', 'wobbles', 'slips', 'squeals', 'grinding',
    'leak', 'leaking', 'frayed', 'bent', 'flat', 'soft', 'spongy',
  };

  @override
  Future<Answer> interpretAnswer(Check check, String text) async {
    // Yes/no alone is ambiguous because questions mix polarity
    // ("Do the brakes stop you?" vs "Any cracks?"), so only clear words count.
    final w = _words(text);
    if (w.intersection(_problemWords).isNotEmpty) return Answer.problem;
    if (w.intersection(_okWords).isNotEmpty) return Answer.ok;
    return Answer.unsure;
  }

  @override
  Future<PhotoAssessment?> assessPhoto(
          Check check, Uint8List bytes, String mediaType) async =>
      null;

  static Set<String> _words(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9' ]"), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.length > 1)
      .toSet();
}

/// Calls the `assess` backend function, which holds the Claude API key.
/// Falls back to [LocalAiService] whenever the backend is unreachable.
class RemoteAiService implements AiService {
  final Uri endpoint;
  final String? apiKey;
  final AiService fallback;
  final http.Client _http;

  RemoteAiService(this.endpoint,
      {this.apiKey, AiService? fallback, http.Client? client})
      : fallback = fallback ?? LocalAiService(),
        _http = client ?? http.Client();

  @override
  String get name => 'Claude via ${endpoint.host}';

  @override
  String? lastError;

  Future<Map<String, dynamic>?> _post(Map<String, dynamic> body) async {
    try {
      final res = await _http
          .post(endpoint,
              headers: {
                'Content-Type': 'application/json',
                if (apiKey != null) 'Authorization': 'Bearer $apiKey',
              },
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) {
        lastError = 'AI backend error ${res.statusCode}';
        return null;
      }
      lastError = null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      lastError = 'AI backend unavailable: $e';
      return null;
    }
  }

  @override
  Future<String?> classifySymptom(String text, List<Symptom> symptoms) async {
    final r = await _post({
      'action': 'classify',
      'text': text,
      'symptoms': [
        for (final s in symptoms)
          {'id': s.id, 'label': s.label, 'phrases': s.customerPhrases}
      ],
    });
    if (r == null) return fallback.classifySymptom(text, symptoms);
    final id = r['symptom_id'] as String?;
    return symptoms.any((s) => s.id == id) ? id : null;
  }

  @override
  Future<Answer> interpretAnswer(Check check, String text) async {
    final r = await _post({
      'action': 'interpret',
      'question': check.customerQuestion,
      'check': check.mcheckText,
      'answer': text,
    });
    if (r == null) return fallback.interpretAnswer(check, text);
    return Answer.values.asNameMap()[r['answer']] ?? Answer.unsure;
  }

  @override
  Future<PhotoAssessment?> assessPhoto(
      Check check, Uint8List bytes, String mediaType) async {
    final r = await _post({
      'action': 'photo',
      'check': {
        'id': check.id,
        'mcheck_text': check.mcheckText,
        'guidance': check.photo.guidance,
        'safety_critical': check.safetyCritical,
      },
      'media_type': mediaType,
      'image_base64': base64Encode(bytes),
    });
    if (r == null) return null;
    final verdict = switch (r['verdict']) {
      'ok' => Answer.ok,
      'problem' => Answer.problem,
      _ => Answer.unsure,
    };
    return PhotoAssessment(verdict, (r['confidence'] as num?)?.toDouble() ?? 0,
        r['observations'] as String? ?? '');
  }
}
