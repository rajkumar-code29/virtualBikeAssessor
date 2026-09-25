// Copyright (c) 2026 Raj Kumar G K. All rights reserved.
// Proprietary and confidential. See LICENSE in the project root.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_services.dart';
import '../data/session_store.dart';
import '../engine/assessment_engine.dart';
import 'result_screen.dart';

class _Message {
  final bool fromBot;
  final String text;
  final String? helper;
  final Uint8List? image;
  final bool safety;
  const _Message(this.fromBot, this.text,
      {this.helper, this.image, this.safety = false});
}

class ChatScreen extends StatefulWidget {
  final AppServices services;
  const ChatScreen(this.services, {super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final AssessmentEngine _engine;
  final _messages = <_Message>[];
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _picker = ImagePicker();

  final _pendingPhotos = <String>[];
  PhotoAssessment? _pendingPhotoAssessment;
  bool _busy = false;
  String? _shownAiError;

  AppServices get _s => widget.services;

  @override
  void initState() {
    super.initState();
    _engine = AssessmentEngine(_s.kb);
    _bot("Hi! I'll help work out what's up with your bike. "
        "You can tap an answer or type in your own words.");
    _showPrompt();
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _bot(String text, {String? helper, bool safety = false}) =>
      _messages.add(_Message(true, text, helper: helper, safety: safety));

  void _showPrompt() {
    final p = _engine.current;
    if (p == null) return;
    _bot(p.text, helper: p.helper, safety: p.safetyCritical);
    if (p.photoGuidance != null && p.kind == PromptKind.check) {
      _bot('📷 A photo helps: ${p.photoGuidance}');
    }
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(0, // list is reversed: 0 is the newest message
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  // ------------------------------------------------------------ answering

  Future<void> _onOption(PromptOption o) async {
    setState(() => _messages.add(_Message(false, o.label)));
    final p = _engine.current!;
    final value =
        p.kind == PromptKind.check ? _combineWithPhoto(p, o.value) : o.value;
    await _submit(value);
  }

  Future<void> _onText() async {
    final text = _text.text.trim();
    if (text.isEmpty || _busy) return;
    _text.clear();
    setState(() {
      _messages.add(_Message(false, text));
      _busy = true;
    });
    final p = _engine.current!;
    try {
      switch (p.kind) {
        case PromptKind.intakeText:
          await _submit('text', freeText: text);
        case PromptKind.reason:
          final id = await _s.ai.classifySymptom(text, _s.kb.symptoms);
          _reportAiError();
          if (id == null) {
            setState(() => _bot(
                "I couldn't quite match that. Could you pick the closest option below?"));
            _scrollToEnd();
          } else {
            setState(() => _bot('Got it: ${_s.kb.symptom(id).label}.'));
            await _submit(id, freeText: text);
          }
        case PromptKind.check:
          final check = _s.kb.checks[p.id]!;
          final answer = await _s.ai.interpretAnswer(check, text);
          _reportAiError();
          await _submit(_combineWithPhoto(p, answer.name), freeText: text);
        case PromptKind.intakeChoice:
        case PromptKind.extra:
          break; // text input hidden for these
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Tells the user (once per distinct error) that the AI failed and the
  /// answer came from offline matching instead.
  void _reportAiError() {
    final err = _s.ai.lastError;
    if (err == null || err == _shownAiError || !mounted) return;
    _shownAiError = err;
    setState(() => _bot('⚠️ AI not available, using offline matching.\n$err'));
    _scrollToEnd();
  }

  /// Combines the customer's answer with any photo verdict.
  /// A photo can resolve "not sure", but it never overrides a reported
  /// problem, and never clears a safety-critical item on its own.
  String _combineWithPhoto(Prompt p, String userValue) {
    final pa = _pendingPhotoAssessment;
    if (userValue != Answer.unsure.name || pa == null || pa.confidence < 0.7) {
      return userValue;
    }
    if (pa.verdict == Answer.problem) return Answer.problem.name;
    if (pa.verdict == Answer.ok && !p.safetyCritical) return Answer.ok.name;
    return userValue;
  }

  Future<void> _submit(String value, {String? freeText}) async {
    setState(() {
      _engine.submit(value,
          freeText: freeText,
          photos: List.of(_pendingPhotos),
          photoAssessment: _pendingPhotoAssessment);
      _pendingPhotos.clear();
      _pendingPhotoAssessment = null;
      _showPrompt();
    });
    if (_engine.isDone) await _finish();
  }

  Future<void> _finish() async {
    final record = SessionRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      assessment: _engine.toJson(),
    );
    await _s.store.save(record);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
          builder: (_) => ResultScreen(_s, _engine.result(), _engine.profile)),
    );
  }

  // --------------------------------------------------------------- photos

  Future<void> _addPhoto() async {
    ImageSource source = ImageSource.gallery;
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS)) {
      final picked = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (c) => SafeArea(
          child: Wrap(children: [
            ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(c, ImageSource.camera)),
            ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from library'),
                onTap: () => Navigator.pop(c, ImageSource.gallery)),
          ]),
        ),
      );
      if (picked == null) return;
      source = picked;
    }

    final file =
        await _picker.pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _messages.add(_Message(false, '', image: bytes));
      _pendingPhotos.add(file.path);
      _busy = true;
    });
    _scrollToEnd();

    try {
      final p = _engine.current;
      if (p?.kind != PromptKind.check) return;
      final check = _s.kb.checks[p!.id]!;
      final pa = await _s.ai.assessPhoto(check, bytes, file.mimeType ?? 'image/jpeg');
      _reportAiError();
      if (!mounted) return;
      setState(() {
        if (pa == null) {
          _bot("Thanks, I've attached that for the technician. "
              "How does it look to you?");
        } else {
          _pendingPhotoAssessment = pa;
          final pct = (pa.confidence * 100).round();
          final verdict = switch (pa.verdict) {
            Answer.ok => 'looks OK',
            Answer.problem => 'looks like it needs attention',
            Answer.unsure => "is hard to judge from this photo",
          };
          _bot('From your photo, this $verdict ($pct% sure). ${pa.observations}\n\n'
              'Does that match what you see?');
        }
      });
      _scrollToEnd();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final p = _engine.current;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Bike assessment')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              // Reversed so the newest message stays pinned to the bottom
              // even when the answer panel below changes height.
              child: ListView.builder(
                controller: _scroll,
                reverse: true,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (_, i) =>
                    _Bubble(_messages[_messages.length - 1 - i]),
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (p != null)
              Material(
                color: theme.colorScheme.surfaceContainer,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Long option lists (e.g. symptoms) scroll rather than
                      // pushing the conversation off screen.
                      ConstrainedBox(
                        constraints: BoxConstraints(
                            maxHeight: MediaQuery.sizeOf(context).height * 0.3),
                        child: SingleChildScrollView(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final o in p.options)
                                ActionChip(
                                  label: Text(o.label),
                                  onPressed: _busy ? null : () => _onOption(o),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (p.allowFreeText) ...[
                        const SizedBox(height: 8),
                        Row(children: [
                          if (p.photoGuidance != null)
                            IconButton(
                              tooltip: 'Add photo',
                              icon: const Icon(Icons.add_a_photo_outlined),
                              onPressed: _busy ? null : _addPhoto,
                            ),
                          Expanded(
                            child: TextField(
                              controller: _text,
                              enabled: !_busy,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _onText(),
                              decoration: const InputDecoration(
                                hintText: 'Or type your answer…',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Send',
                            icon: const Icon(Icons.send),
                            onPressed: _busy ? null : _onText,
                          ),
                        ]),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final _Message m;
  const _Bubble(this.m);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = m.fromBot ? cs.surfaceContainerHighest : cs.primaryContainer;
    final fg = m.fromBot ? cs.onSurface : cs.onPrimaryContainer;

    return Align(
      alignment: m.fromBot ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: m.image != null
              ? const EdgeInsets.all(4)
              : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: m.safety ? Border.all(color: cs.error, width: 1.5) : null,
          ),
          child: m.image != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(m.image!, height: 180, fit: BoxFit.cover))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (m.safety)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('SAFETY CHECK',
                            style: TextStyle(
                                color: cs.error,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8)),
                      ),
                    Text(m.text, style: TextStyle(color: fg)),
                    if (m.helper != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.science_outlined,
                                size: 18, color: cs.primary),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text('Quick check: ${m.helper}',
                                    style: TextStyle(color: cs.onSurface))),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
