// Copyright (c) 2026 Raj Kumar G K. All rights reserved.
// Proprietary and confidential. See LICENSE in the project root.

/// The diagnostic engine: runs intake, routes to a symptom (or the full M-check),
/// picks the next most useful question, and produces findings.
///
/// The engine is deterministic and owns all safety logic. The AI layer only
/// translates free text / photos into the engine's answer values.
library;

import '../kb/knowledge_base.dart';

enum Answer { ok, problem, unsure }

enum Confidence { high, medium, low }

enum PromptKind { intakeText, intakeChoice, reason, check, extra }

class PromptOption {
  final String value;
  final String label;
  const PromptOption(this.value, this.label);
}

class Prompt {
  final String id;
  final PromptKind kind;
  final String text;
  final String? helper; // self-test instructions
  final List<PromptOption> options;
  final bool allowFreeText;
  final String? photoGuidance;
  final bool safetyCritical;

  const Prompt({
    required this.id,
    required this.kind,
    required this.text,
    this.helper,
    this.options = const [],
    this.allowFreeText = true,
    this.photoGuidance,
    this.safetyCritical = false,
  });
}

/// What a vision model said about a photo for one check.
class PhotoAssessment {
  final Answer verdict;
  final double confidence; // 0..1
  final String observations;
  const PhotoAssessment(this.verdict, this.confidence, this.observations);

  Map<String, dynamic> toJson() => {
        'verdict': verdict.name,
        'confidence': confidence,
        'observations': observations,
      };
}

class Turn {
  final String promptId;
  final String question;
  final String value;
  final String? freeText;
  final List<String> photos;
  final PhotoAssessment? photoAssessment;
  final DateTime at;

  Turn(this.promptId, this.question, this.value,
      {this.freeText, this.photos = const [], this.photoAssessment})
      : at = DateTime.now();

  Map<String, dynamic> toJson() => {
        'prompt_id': promptId,
        'question': question,
        'value': value,
        if (freeText != null) 'free_text': freeText,
        if (photos.isNotEmpty) 'photos': photos,
        if (photoAssessment != null) 'photo_assessment': photoAssessment!.toJson(),
        'at': at.toIso8601String(),
      };
}

class BikeProfile {
  String? makeModel;
  bool isEbike = false;
  String brakeType = 'not_sure';
  String suspension = 'none';

  Map<String, dynamic> toJson() => {
        'make_model': makeModel,
        'is_ebike': isEbike,
        'brake_type': brakeType,
        'suspension': suspension,
      };
}

class Finding {
  final String causeId;
  final String label;
  final Confidence confidence;
  final bool confirmedByUser; // false = inferred as "most likely" only
  final bool needsHandsOnCheck;
  final bool safetyCritical;
  final bool stopRiding;
  final String? message;
  final List<String> repairs; // first = most likely fix
  final bool diyPossible;
  final String? tier;
  final String? serviceUpsell;
  final List<String> products;
  final String? advice;

  const Finding({
    required this.causeId,
    required this.label,
    required this.confidence,
    required this.confirmedByUser,
    required this.needsHandsOnCheck,
    required this.safetyCritical,
    required this.stopRiding,
    required this.message,
    required this.repairs,
    required this.diyPossible,
    required this.tier,
    required this.serviceUpsell,
    required this.products,
    required this.advice,
  });

  Map<String, dynamic> toJson() => {
        'cause_id': causeId,
        'confidence': confidence.name,
        'confirmed_by_user': confirmedByUser,
        'needs_hands_on_check': needsHandsOnCheck,
        'stop_riding': stopRiding,
        'repairs': repairs,
      };
}

class AssessmentResult {
  final String? symptomId;
  final List<Finding> findings;
  final List<String> unsureChecks; // answered "not sure": a tech should look
  final bool cannotService;
  final List<String> cannotServiceMessages;
  final List<String> bookingNotes;

  const AssessmentResult({
    required this.symptomId,
    required this.findings,
    required this.unsureChecks,
    required this.cannotService,
    required this.cannotServiceMessages,
    required this.bookingNotes,
  });

  bool get stopRiding => findings.any((f) => f.stopRiding);

  Map<String, dynamic> toJson() => {
        'symptom_id': symptomId,
        'findings': [for (final f in findings) f.toJson()],
        'unsure_checks': unsureChecks,
        'cannot_service': cannotService,
        'booking_notes': bookingNotes,
      };
}

class AssessmentEngine {
  final KnowledgeBase kb;
  final BikeProfile profile = BikeProfile();
  final List<Turn> turns = [];

  Symptom? symptom;
  final Map<String, double> posterior = {};
  final Map<String, Answer> checkAnswers = {};
  final Map<String, PhotoAssessment> photoAssessments = {};
  final Set<String> supportedCauses = {};
  final Set<String> askedExtras = {};

  int _intakeIndex = 0;
  bool _routed = false;
  bool _stopped = false;
  List<String> _fullCheckQueue = const [];
  Prompt? _current;

  // Likelihood multipliers used to update cause probabilities. Tuned by hand
  // for now; replace with values fitted from confirmed workshop outcomes.
  static const problemFactor = 5.0;
  static const okFactor = 0.15;
  static const supportFactor = 4.0;
  static const weakenFactor = 0.2;
  static const askThreshold = 0.1;
  static const possibleThreshold = 0.15;

  static const _optionLabels = {
    'yes': 'Yes',
    'no': 'No',
    'rim': 'Rim brakes (pads grip the wheel rim)',
    'mechanical_disc': 'Disc brakes with cables',
    'hydraulic_disc': 'Hydraulic disc brakes (hoses, no cables)',
    'not_sure': "I'm not sure",
    'none': 'None',
    'front': 'Front only',
    'front_and_rear': 'Front and rear',
  };

  static const checkOptions = [
    PromptOption('ok', 'All good'),
    PromptOption('problem', "Something's wrong"),
    PromptOption('unsure', 'Not sure'),
  ];

  AssessmentEngine(this.kb) {
    _current = _intakePrompt();
  }

  Prompt? get current => _current;
  bool get isDone => _current == null;

  // ---------------------------------------------------------------- intake

  Prompt? _intakePrompt() {
    if (_intakeIndex >= kb.intake.length) return null;
    final q = kb.intake[_intakeIndex];
    if (q.id == 'reason') {
      return Prompt(
        id: q.id,
        kind: PromptKind.reason,
        text: q.ask,
        options: [
          for (final s in kb.symptoms)
            if (s.id != 'ebike_problem' || profile.isEbike)
              PromptOption(s.id, s.label)
        ],
      );
    }
    if (q.options.isEmpty) {
      return Prompt(
        id: q.id,
        kind: PromptKind.intakeText,
        text: q.ask,
        photoGuidance: q.photo,
        options: const [PromptOption('skip', 'Skip')],
      );
    }
    return Prompt(
      id: q.id,
      kind: PromptKind.intakeChoice,
      text: q.ask,
      allowFreeText: false,
      options: [
        for (final o in q.options) PromptOption(o, _optionLabels[o] ?? o)
      ],
    );
  }

  /// Records an answer to the current prompt and advances.
  ///
  /// [value] is an option value (or 'text' for free text on intake). For
  /// check prompts it must be an [Answer] name. For the reason prompt it
  /// must be a symptom id (the UI classifies free text first).
  void submit(String value,
      {String? freeText,
      List<String> photos = const [],
      PhotoAssessment? photoAssessment}) {
    final p = _current;
    if (p == null) throw StateError('Assessment already finished');
    turns.add(Turn(p.id, p.text, value,
        freeText: freeText, photos: photos, photoAssessment: photoAssessment));

    switch (p.kind) {
      case PromptKind.intakeText:
        if (p.id == 'bike_make_model' && value != 'skip') {
          profile.makeModel = freeText ?? value;
        }
        _intakeIndex++;
      case PromptKind.intakeChoice:
        _applyIntake(p.id, value);
        _intakeIndex++;
      case PromptKind.reason:
        _route(value);
      case PromptKind.check:
        _recordCheck(p.id, Answer.values.byName(value), photoAssessment);
      case PromptKind.extra:
        _recordExtra(p.id, value);
    }
    _current = _routed ? _nextDiagnosticPrompt() : _intakePrompt();
  }

  void _applyIntake(String id, String value) {
    switch (id) {
      case 'is_ebike':
        profile.isEbike = value == 'yes';
      case 'brake_type':
        profile.brakeType = value;
      case 'has_suspension':
        profile.suspension = value;
    }
  }

  // --------------------------------------------------------------- routing

  void _route(String symptomId) {
    final s = kb.symptom(symptomId);
    symptom = s;
    _routed = true;
    if (s.id == 'ebike_problem') profile.isEbike = true;

    if (s.isFullCheck) {
      _fullCheckQueue = _buildFullCheckQueue();
    } else {
      posterior.addAll(s.candidates);
      _normalise();
    }
  }

  List<String> _buildFullCheckQueue() {
    final applicable = <Check>[];
    for (final section in kb.sections) {
      if (!_applies(section.appliesIf)) continue;
      for (final c in section.checks) {
        if (_askable(c)) applicable.add(c);
      }
    }
    // eBike eligibility first, then safety-critical, then the rest in form order.
    final ebike = applicable.where((c) => c.sectionId == 'ebike');
    final rest = applicable.where((c) => c.sectionId != 'ebike');
    return [
      ...ebike.where((c) => c.stopWork),
      ...ebike.where((c) => !c.stopWork),
      ...rest.where((c) => c.safetyCritical),
      ...rest.where((c) => !c.safetyCritical),
    ].map((c) => c.id).toList();
  }

  /// A check becomes a question only if it applies to this bike and a
  /// customer can answer it. Booking notes are reminders, not questions.
  bool _askable(Check c) =>
      _applies(c.appliesIf) &&
      c.customerQuestion != null &&
      c.onFail.outcome != 'booking_note';

  /// Evaluates the small set of `applies_if` expressions used in the KB.
  /// Unknown expressions return true: asking an extra question is safer than
  /// skipping one.
  bool _applies(String? expr) {
    if (expr == null) return true;
    if (expr.startsWith('brake_type')) {
      if (profile.brakeType == 'not_sure') return true;
      final allowed =
          RegExp(r"'(\w+)'").allMatches(expr).map((m) => m.group(1)).toSet();
      return allowed.contains(profile.brakeType);
    }
    if (expr.contains('is_ebike')) return profile.isEbike;
    if (expr.contains('has_suspension')) return profile.suspension != 'none';
    return true;
  }

  // --------------------------------------------------------- next question

  Prompt? _nextDiagnosticPrompt() {
    if (_stopped) return null;

    // eBike eligibility gates every flow: if the shop can't touch the bike,
    // nothing else matters.
    if (profile.isEbike) {
      for (final c in kb.sections.firstWhere((s) => s.id == 'ebike').checks) {
        if (c.stopWork && !checkAnswers.containsKey(c.id)) return _checkPrompt(c);
      }
    }

    final s = symptom!;
    if (s.isFullCheck) {
      for (final id in _fullCheckQueue) {
        if (!checkAnswers.containsKey(id)) return _checkPrompt(kb.checks[id]!);
      }
      return null;
    }
    return _nextSymptomPrompt(s);
  }

  Prompt? _nextSymptomPrompt(Symptom s) {
    // Safety-critical candidates are always asked about; a remote diagnosis
    // must never silently skip them.
    for (final id in s.askOrder) {
      final c = kb.checks[id];
      if (c != null &&
          c.safetyCritical &&
          _askable(c) &&
          !checkAnswers.containsKey(id)) {
        return _checkPrompt(c);
      }
    }

    // Otherwise ask the question about the most likely remaining cause, and
    // stop once every remaining question targets an unlikely cause.
    String? bestId;
    double bestScore = askThreshold;
    ExtraQuestion? bestExtra;

    for (final id in s.askOrder) {
      final c = kb.checks[id];
      if (c == null || !_askable(c) || checkAnswers.containsKey(id)) continue;
      final score = posterior[id] ?? 0;
      if (score > bestScore) {
        bestScore = score;
        bestId = id;
        bestExtra = null;
      }
    }
    for (final q in s.extraQuestions) {
      if (askedExtras.contains(q.id)) continue;
      final targets = {
        for (final o in q.options) ...o.supports,
        for (final o in q.options) ...o.weakens
      };
      final score = targets.map((t) => posterior[t] ?? 0).fold(0.0, _max);
      if (score > bestScore) {
        bestScore = score;
        bestExtra = q;
        bestId = null;
      }
    }

    if (bestExtra != null) {
      return Prompt(
        id: bestExtra.id,
        kind: PromptKind.extra,
        text: bestExtra.ask,
        allowFreeText: false,
        options: [
          for (final o in bestExtra.options) PromptOption(o.value, o.label),
          const PromptOption('unsure', 'Not sure'),
        ],
      );
    }
    if (bestId != null) return _checkPrompt(kb.checks[bestId]!);
    return null;
  }

  static double _max(double a, double b) => a > b ? a : b;

  Prompt _checkPrompt(Check c) => Prompt(
        id: c.id,
        kind: PromptKind.check,
        text: c.customerQuestion!,
        helper: c.selfTest,
        options: checkOptions,
        photoGuidance: c.photo.needed ? c.photo.guidance : null,
        safetyCritical: c.safetyCritical,
      );

  // --------------------------------------------------------------- updates

  void _recordCheck(String id, Answer answer, PhotoAssessment? photo) {
    checkAnswers[id] = answer;
    if (photo != null) photoAssessments[id] = photo;
    if (answer == Answer.ok) supportedCauses.remove(id);

    final c = kb.checks[id]!;
    if (answer == Answer.problem && c.stopWork) {
      _stopped = true; // no further work can be carried out
      return;
    }
    if (posterior.containsKey(id)) {
      if (answer == Answer.problem) posterior[id] = posterior[id]! * problemFactor;
      if (answer == Answer.ok) posterior[id] = posterior[id]! * okFactor;
      _normalise();
    }
  }

  void _recordExtra(String id, String value) {
    askedExtras.add(id);
    final q = symptom!.extraQuestions.firstWhere((q) => q.id == id);
    final option = q.options.where((o) => o.value == value).firstOrNull;
    if (option == null) return; // "not sure"
    for (final t in option.supports) {
      posterior[t] = (posterior[t] ?? 0.05) * supportFactor;
      supportedCauses.add(t);
    }
    for (final t in option.weakens) {
      if (posterior.containsKey(t)) posterior[t] = posterior[t]! * weakenFactor;
      supportedCauses.remove(t);
    }
    _normalise();
  }

  void _normalise() {
    final total = posterior.values.fold(0.0, (a, b) => a + b);
    if (total <= 0) return;
    posterior.updateAll((_, v) => v / total);
  }

  // ---------------------------------------------------------------- result

  AssessmentResult result() {
    final findings = <Finding>[];
    final cannot = <String>[];
    final unsure = <String>[];

    checkAnswers.forEach((id, answer) {
      final c = kb.checks[id]!;
      if (answer == Answer.unsure) unsure.add(id);
      if (answer != Answer.problem) return;
      if (c.onFail.outcome == 'cannot_service') {
        cannot.add(c.onFail.message ?? c.mcheckText);
        return;
      }
      findings.add(_findingForCheck(c, confirmed: true));
    });

    for (final id in supportedCauses) {
      if (findings.any((f) => f.causeId == id)) continue;
      findings.add(_findingForCause(id, confirmed: true));
    }

    // Symptom flow with nothing confirmed: report the most likely causes as
    // possibilities for a hands-on check rather than a verdict.
    final s = symptom;
    if (s != null && !s.isFullCheck && findings.isEmpty && cannot.isEmpty) {
      final ranked = posterior.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in ranked) {
        if (e.value < possibleThreshold && findings.isNotEmpty) break;
        if (checkAnswers[e.key] == Answer.ok) continue;
        findings.add(_findingForCause(e.key, confirmed: false));
        if (findings.length == 2) break;
      }
    }

    // Safety-critical and stop-riding items first.
    findings.sort((a, b) {
      int rank(Finding f) => f.stopRiding ? 0 : (f.safetyCritical ? 1 : 2);
      return rank(a).compareTo(rank(b));
    });

    final notes = <String>[];
    if (profile.isEbike) {
      for (final c in kb.sections.firstWhere((s) => s.id == 'ebike').checks) {
        if (c.onFail.outcome == 'booking_note') {
          notes.add(c.onFail.message ?? c.customerQuestion ?? c.mcheckText);
        }
      }
    }
    for (final id in checkAnswers.keys) {
      final advice = kb.checks[id]!.advice;
      if (advice != null) notes.add(advice);
    }

    return AssessmentResult(
      symptomId: s?.id,
      findings: findings,
      unsureChecks: unsure,
      cannotService: cannot.isNotEmpty,
      cannotServiceMessages: cannot,
      bookingNotes: notes,
    );
  }

  Finding _findingForCause(String id, {required bool confirmed}) {
    final c = kb.checks[id];
    if (c != null) return _findingForCheck(c, confirmed: confirmed);
    final n = kb.nonCheckCauses[id]!;
    return Finding(
      causeId: id,
      label: n.label,
      confidence: confirmed ? Confidence.medium : Confidence.low,
      confirmedByUser: confirmed,
      needsHandsOnCheck: !confirmed || n.remoteConfidence == RemoteConfidence.techOnly,
      safetyCritical: false,
      stopRiding: false,
      message: null,
      repairs: n.repairs,
      diyPossible: n.diyPossible,
      tier: null,
      serviceUpsell: null,
      products: const [],
      advice: null,
    );
  }

  Finding _findingForCheck(Check c, {required bool confirmed}) {
    final photo = photoAssessments[c.id];
    final Confidence confidence;
    if (!confirmed || c.remoteConfidence == RemoteConfidence.techOnly) {
      confidence = Confidence.low;
    } else if (photo != null &&
        photo.verdict == Answer.problem &&
        photo.confidence >= 0.7) {
      confidence = Confidence.high;
    } else {
      confidence = Confidence.medium;
    }

    return Finding(
      causeId: c.id,
      label: c.faultLabel,
      confidence: confidence,
      confirmedByUser: confirmed,
      needsHandsOnCheck: !confirmed ||
          c.remoteConfidence == RemoteConfidence.techOnly ||
          c.safetyCritical,
      safetyCritical: c.safetyCritical,
      // stop_riding_if conditions can't be verified remotely, so a confirmed
      // safety-critical fault is treated as "stop riding" too.
      stopRiding: confirmed &&
          (c.onFail.stopRiding ||
              (c.safetyCritical && c.onFail.stopRidingIf != null)),
      message: c.onFail.message,
      repairs: c.onFail.repairs,
      diyPossible: c.onFail.diyPossible,
      tier: c.tier,
      serviceUpsell: c.onFail.serviceUpsell ?? symptom?.serviceUpsell,
      products: c.onFail.products,
      advice: c.advice,
    );
  }

  Map<String, dynamic> toJson() => {
        'kb_version': kb.version,
        'bike': profile.toJson(),
        'symptom_id': symptom?.id,
        'turns': [for (final t in turns) t.toJson()],
        'posterior': posterior,
        'result': isDone ? result().toJson() : null,
      };
}
