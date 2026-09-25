// Copyright (c) 2026 Raj Kumar G K. All rights reserved.
// Proprietary and confidential. See LICENSE in the project root.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../engine/assessment_engine.dart';
import '../kb/knowledge_base.dart';
import 'ai_service.dart';

/// Calls the Gemini API directly from the app.
///
/// For prototyping only: the API key ships inside the app, so anyone with the
/// app binary could extract it. Before real customers use it, move these calls
/// behind the backend function (see supabase/functions/assess).
class GeminiAiService implements AiService {
  final String apiKey;
  final String model;
  final AiService fallback;
  final http.Client _http;

  @override
  String? lastError;

  GeminiAiService(this.apiKey,
      {this.model = 'gemini-3.8-flash', AiService? fallback, http.Client? client})
      : fallback = fallback ?? LocalAiService(),
        _http = client ?? http.Client();

  @override
  String get name => 'Gemini ($model)';

  static const _system =
      'You help a bike workshop assess bikes remotely, using the workshop\'s M-check. '
      'Customers describe problems in everyday words and may be unsure of bike terminology. '
      'Be conservative: if something is unclear, say so rather than guessing. '
      'Never judge a safety-critical item (brakes, frame, headset, hubs, handlebars, '
      'eBike battery) as fine unless the evidence is clear.';

  /// Sends one request and returns the parsed JSON reply, or null on failure
  /// (the failure reason is kept in [lastError]).
  Future<Map<String, dynamic>?> _ask(
      List<Map<String, dynamic>> parts, Map<String, dynamic> schema) async {
    final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent');
    try {
      final res = await _http
          .post(uri,
              headers: {
                'Content-Type': 'application/json',
                'x-goog-api-key': apiKey,
                // Lets the key be restricted to this app in Google Cloud.
                'X-Ios-Bundle-Identifier': 'uk.bikeassessor.bikeAssessor',
              },
              body: jsonEncode({
                'systemInstruction': {
                  'parts': [
                    {'text': _system}
                  ]
                },
                'contents': [
                  {'role': 'user', 'parts': parts}
                ],
                'generationConfig': {
                  'responseMimeType': 'application/json',
                  'responseSchema': schema,
                },
              }))
          .timeout(const Duration(seconds: 60));

      if (res.statusCode != 200) {
        lastError = 'Gemini error ${res.statusCode}: ${_errorMessage(res.body)}';
        debugPrint(lastError);
        return null;
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final text = (body['candidates'] as List?)
          ?.firstOrNull?['content']?['parts']
          ?.firstWhere((p) => p['text'] != null, orElse: () => null)?['text'];
      if (text is! String) {
        lastError = 'Gemini returned no answer '
            '(${body['promptFeedback']?['blockReason'] ?? 'no text'})';
        debugPrint(lastError);
        return null;
      }
      lastError = null;
      return jsonDecode(_stripFences(text)) as Map<String, dynamic>;
    } catch (e) {
      lastError = 'Gemini unavailable: $e';
      debugPrint(lastError);
      return null;
    }
  }

  static String _errorMessage(String body) {
    try {
      return (jsonDecode(body)['error']?['message'] as String?) ?? body;
    } catch (_) {
      return body;
    }
  }

  static String _stripFences(String s) => s
      .trim()
      .replaceFirst(RegExp(r'^```(json)?'), '')
      .replaceFirst(RegExp(r'```$'), '')
      .trim();

  @override
  Future<String?> classifySymptom(String text, List<Symptom> symptoms) async {
    final list = symptoms
        .map((s) => '- ${s.id}: ${s.label} (e.g. ${s.customerPhrases.join('; ')})')
        .join('\n');
    final r = await _ask([
      {
        'text': 'A customer described their bike problem as:\n'
            '<customer>$text</customer>\n\n'
            'Pick the single best matching symptom id from this list. Use '
            '"general_check" if they just want the bike checked over, and "none" '
            "if nothing fits or it's too vague.\n$list"
      }
    ], {
      'type': 'OBJECT',
      'properties': {
        'symptom_id': {
          'type': 'STRING',
          'enum': [...symptoms.map((s) => s.id), 'none'],
        },
      },
      'required': ['symptom_id'],
    });
    if (r == null) return fallback.classifySymptom(text, symptoms);
    final id = r['symptom_id'];
    return symptoms.any((s) => s.id == id) ? id as String : null;
  }

  @override
  Future<Answer> interpretAnswer(Check check, String text) async {
    final r = await _ask([
      {
        'text': 'The workshop check is: "${check.mcheckText}"\n'
            'We asked the customer: "${check.customerQuestion}"\n'
            'They replied: <customer>$text</customer>\n\n'
            'Classify the reply for this check:\n'
            '- "ok": the check passes (no fault described)\n'
            '- "problem": they describe a fault this check would fail on\n'
            '- "unsure": they don\'t know, didn\'t answer, or it\'s ambiguous\n'
            'Watch the question\'s polarity: "yes" can mean ok or problem '
            'depending on how it was asked.'
      }
    ], {
      'type': 'OBJECT',
      'properties': {
        'answer': {
          'type': 'STRING',
          'enum': ['ok', 'problem', 'unsure'],
        },
      },
      'required': ['answer'],
    });
    if (r == null) return fallback.interpretAnswer(check, text);
    return Answer.values.asNameMap()[r['answer']] ?? Answer.unsure;
  }

  @override
  Future<PhotoAssessment?> assessPhoto(
      Check check, Uint8List bytes, String mediaType) async {
    final r = await _ask([
      {
        'inline_data': {'mime_type': mediaType, 'data': base64Encode(bytes)}
      },
      {
        'text': 'Workshop check: "${check.mcheckText}"\n'
            'The customer was asked for: ${check.photo.guidance ?? 'a photo of this area'}.\n'
            '${check.safetyCritical ? 'This is a SAFETY-CRITICAL check. Only return "ok" if the photo clearly shows the part in good condition.\n' : ''}'
            'Judge only this check from the photo.\n'
            '- verdict "ok" / "problem" / "unclear" (use "unclear" if the relevant part isn\'t visible or in focus)\n'
            '- confidence 0-1\n'
            '- observations: one or two plain-English sentences for the customer about what you can see'
      }
    ], {
      'type': 'OBJECT',
      'properties': {
        'verdict': {
          'type': 'STRING',
          'enum': ['ok', 'problem', 'unclear'],
        },
        'confidence': {'type': 'NUMBER'},
        'observations': {'type': 'STRING'},
      },
      'required': ['verdict', 'confidence', 'observations'],
    });
    if (r == null) return null;
    final verdict = switch (r['verdict']) {
      'ok' => Answer.ok,
      'problem' => Answer.problem,
      _ => Answer.unsure,
    };
    return PhotoAssessment(verdict,
        ((r['confidence'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
        r['observations'] as String? ?? '');
  }
}
