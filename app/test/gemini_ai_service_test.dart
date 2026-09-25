// Copyright (c) 2026 Raj Kumar G K. All rights reserved.
// Proprietary and confidential. See LICENSE in the project root.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bike_assessor/ai/gemini_ai_service.dart';
import 'package:bike_assessor/engine/assessment_engine.dart';
import 'package:bike_assessor/kb/knowledge_base.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A Gemini generateContent response whose text part is [json].
http.Response geminiReply(Map<String, dynamic> json) => http.Response(
      jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': jsonEncode(json)}
              ]
            }
          }
        ]
      }),
      200,
    );

void main() {
  late KnowledgeBase kb;
  setUpAll(() {
    kb = KnowledgeBase.fromJson(
        jsonDecode(File('assets/kb/mcheck_kb.json').readAsStringSync()));
  });

  test('classify: sends key header + JSON schema, parses the symptom', () async {
    late http.Request sent;
    final ai = GeminiAiService('test-key',
        client: MockClient((req) async {
          sent = req;
          return geminiReply({'symptom_id': 'gears_slipping'});
        }));

    final id = await ai.classifySymptom('it jumps about in top gear', kb.symptoms);

    expect(id, 'gears_slipping');
    expect(ai.lastError, isNull);
    expect(sent.url.path, '/v1beta/models/gemini-3.8-flash:generateContent');
    expect(sent.headers['x-goog-api-key'], 'test-key');
    expect(sent.url.queryParameters, isEmpty); // key never in the URL
    final body = jsonDecode(sent.body);
    expect(body['generationConfig']['responseMimeType'], 'application/json');
    expect(body['generationConfig']['responseSchema']['properties']['symptom_id']['enum'],
        contains('none'));
  });

  test('classify: "none" means no match', () async {
    final ai = GeminiAiService('k',
        client: MockClient((_) async => geminiReply({'symptom_id': 'none'})));
    expect(await ai.classifySymptom('hello', kb.symptoms), isNull);
  });

  test('photo: sends the image inline and clamps confidence', () async {
    late Map body;
    final ai = GeminiAiService('k', client: MockClient((req) async {
      body = jsonDecode(req.body);
      return geminiReply(
          {'verdict': 'problem', 'confidence': 1.4, 'observations': 'Pads are thin.'});
    }));

    final pa = await ai.assessPhoto(
        kb.checks['brake_pads']!, Uint8List.fromList([1, 2, 3]), 'image/jpeg');

    expect(pa!.verdict, Answer.problem);
    expect(pa.confidence, 1.0);
    final parts = body['contents'][0]['parts'] as List;
    expect(parts.first['inline_data']['mime_type'], 'image/jpeg');
    expect(parts.first['inline_data']['data'], base64Encode([1, 2, 3]));
    expect(parts.last['text'], contains('SAFETY-CRITICAL'));
  });

  test('bad key: falls back to offline matching and reports the error', () async {
    final ai = GeminiAiService('bad', client: MockClient((_) async => http.Response(
        jsonEncode({'error': {'message': 'API key not valid.'}}), 400)));

    final id = await ai.classifySymptom('chain skips', kb.symptoms);

    expect(id, 'gears_slipping'); // from the keyword fallback
    expect(ai.lastError, contains('API key not valid.'));
    expect(await ai.assessPhoto(kb.checks['brake_pads']!, Uint8List(0), 'image/jpeg'),
        isNull);
  });
}
