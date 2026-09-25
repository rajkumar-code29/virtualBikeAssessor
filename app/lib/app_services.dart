// Copyright (c) 2026 Raj Kumar G K. All rights reserved.
// Proprietary and confidential. See LICENSE in the project root.

import 'dart:convert';

import 'package:flutter/services.dart';

import 'ai/ai_service.dart';
import 'ai/gemini_ai_service.dart';
import 'data/session_store.dart';
import 'engine/estimate.dart';
import 'kb/knowledge_base.dart';

/// Everything the screens need, loaded once at startup.
class AppServices {
  final KnowledgeBase kb;
  final ShopConfig shop;
  final AiService ai;
  final SessionStore store;

  AppServices(this.kb, this.shop, this.ai, this.store);

  /// Set at build time from secrets.json:
  /// `flutter run --release --dart-define-from-file=secrets.json`
  /// GEMINI_API_KEY wins; otherwise ASSESS_ENDPOINT (the backend function);
  /// otherwise the app runs offline.
  static const _geminiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const _geminiModel =
      String.fromEnvironment('GEMINI_MODEL', defaultValue: 'gemini-3.8-flash');
  static const _endpoint = String.fromEnvironment('ASSESS_ENDPOINT');
  static const _apiKey = String.fromEnvironment('ASSESS_API_KEY');

  static Future<AppServices> load() async {
    final kb = KnowledgeBase.fromJson(
        jsonDecode(await rootBundle.loadString('assets/kb/mcheck_kb.json')));
    final shop = ShopConfig.fromJson(
        jsonDecode(await rootBundle.loadString('assets/config/shop_config.json')));
    final AiService ai = _geminiKey.isNotEmpty
        ? GeminiAiService(_geminiKey, model: _geminiModel)
        : _endpoint.isNotEmpty
            ? RemoteAiService(Uri.parse(_endpoint),
                apiKey: _apiKey.isEmpty ? null : _apiKey)
            : LocalAiService();
    return AppServices(kb, shop, ai, SessionStore());
  }
}
