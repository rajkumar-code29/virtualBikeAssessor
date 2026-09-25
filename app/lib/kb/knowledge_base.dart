// Copyright (c) 2026 Raj Kumar G K. All rights reserved.
// Proprietary and confidential. See LICENSE in the project root.

/// Typed view over assets/kb/mcheck_kb.json.
///
/// Pure Dart (no Flutter imports) so the same code can run on a Dart server
/// later when the engine is exposed as an API for other apps.
library;

enum RemoteConfidence { photo, selfTest, conversation, techOnly }

RemoteConfidence _parseConfidence(String? s) => switch (s) {
      'photo' => RemoteConfidence.photo,
      'self_test' => RemoteConfidence.selfTest,
      'tech_only' => RemoteConfidence.techOnly,
      _ => RemoteConfidence.conversation,
    };

class PhotoRequest {
  final bool needed;
  final String? guidance;
  const PhotoRequest({required this.needed, this.guidance});

  factory PhotoRequest.fromJson(Map<String, dynamic>? j) =>
      PhotoRequest(needed: j?['needed'] == true, guidance: j?['guidance']);
}

class OnFail {
  final List<String> repairs;
  final String? outcome; // cannot_service, not_repairable, booking_note, product_suggestion
  final String? message;
  final bool stopRiding;
  final String? stopRidingIf;
  final bool diyPossible;
  final String? serviceUpsell;
  final List<String> products;

  const OnFail({
    this.repairs = const [],
    this.outcome,
    this.message,
    this.stopRiding = false,
    this.stopRidingIf,
    this.diyPossible = false,
    this.serviceUpsell,
    this.products = const [],
  });

  factory OnFail.fromJson(Map<String, dynamic>? j) => OnFail(
        repairs: List<String>.from(j?['repairs'] ?? const []),
        outcome: j?['outcome'],
        message: j?['message'],
        stopRiding: j?['stop_riding'] == true,
        stopRidingIf: j?['stop_riding_if'],
        diyPossible: j?['diy_possible'] == true,
        serviceUpsell: j?['service_upsell'],
        products: List<String>.from(j?['products'] ?? const []),
      );
}

class Check {
  final String id;
  final String sectionId;
  final String mcheckText;
  final String faultLabel; // customer-facing name for a failed check
  final String? tier;
  final bool safetyCritical;
  final bool stopWork;
  final String? appliesIf;
  final String? customerQuestion;
  final String? selfTest;
  final PhotoRequest photo;
  final String? videoGuidance;
  final RemoteConfidence remoteConfidence;
  final OnFail onFail;
  final String? advice;

  const Check({
    required this.id,
    required this.sectionId,
    required this.mcheckText,
    required this.faultLabel,
    required this.tier,
    required this.safetyCritical,
    required this.stopWork,
    required this.appliesIf,
    required this.customerQuestion,
    required this.selfTest,
    required this.photo,
    required this.videoGuidance,
    required this.remoteConfidence,
    required this.onFail,
    required this.advice,
  });

  factory Check.fromJson(Map<String, dynamic> j, String sectionId) => Check(
        id: j['id'],
        sectionId: sectionId,
        mcheckText: j['mcheck_text'],
        faultLabel: j['fault_label'] ?? j['mcheck_text'],
        tier: j['tier'],
        safetyCritical: j['safety_critical'] == true,
        stopWork: j['stop_work'] == true,
        appliesIf: j['applies_if'],
        customerQuestion: j['customer_question'],
        selfTest: j['self_test'],
        photo: PhotoRequest.fromJson(j['photo_request']),
        videoGuidance: j['video_request']?['guidance'],
        remoteConfidence: _parseConfidence(j['remote_confidence']),
        onFail: OnFail.fromJson(j['on_fail']),
        advice: j['advice'],
      );
}

class Section {
  final String id;
  final String label;
  final String? appliesIf;
  final List<Check> checks;
  const Section(this.id, this.label, this.appliesIf, this.checks);
}

class Repair {
  final String id;
  final String label;
  final List<String> parts;
  final bool perPosition;
  final String? note;
  const Repair(this.id, this.label, this.parts, this.perPosition, this.note);
}

class AnswerOption {
  final String value;
  final String label;
  final List<String> supports;
  final List<String> weakens;
  const AnswerOption(this.value, this.label,
      {this.supports = const [], this.weakens = const []});

  factory AnswerOption.fromJson(Map<String, dynamic> j) => AnswerOption(
        j['value'],
        j['label'],
        supports: List<String>.from(j['supports'] ?? const []),
        weakens: List<String>.from(j['weakens'] ?? const []),
      );
}

class ExtraQuestion {
  final String id;
  final String ask;
  final List<AnswerOption> options;
  const ExtraQuestion(this.id, this.ask, this.options);
}

class Symptom {
  final String id;
  final String label;
  final List<String> customerPhrases;
  final bool isFullCheck;
  final bool safetyCritical;
  final Map<String, double> candidates;
  final List<String> askOrder;
  final List<ExtraQuestion> extraQuestions;
  final String? serviceUpsell;

  const Symptom({
    required this.id,
    required this.label,
    required this.customerPhrases,
    required this.isFullCheck,
    required this.safetyCritical,
    required this.candidates,
    required this.askOrder,
    required this.extraQuestions,
    required this.serviceUpsell,
  });

}

class NonCheckCause {
  final String id;
  final String label;
  final List<String> repairs;
  final bool diyPossible;
  final RemoteConfidence remoteConfidence;
  const NonCheckCause(
      this.id, this.label, this.repairs, this.diyPossible, this.remoteConfidence);
}

class IntakeQuestion {
  final String id;
  final String ask;
  final List<String> options;
  final String? photo;
  const IntakeQuestion(this.id, this.ask, this.options, this.photo);
}

class KnowledgeBase {
  final String version;
  final List<Section> sections;
  final Map<String, Check> checks;
  final Map<String, Repair> repairs;
  final List<Symptom> symptoms;
  final Map<String, NonCheckCause> nonCheckCauses;
  final List<IntakeQuestion> intake;
  final List<String> tierOrder;
  final Map<String, String> tierLabels;
  final Map<String, String> serviceLabels;

  KnowledgeBase._({
    required this.version,
    required this.sections,
    required this.checks,
    required this.repairs,
    required this.symptoms,
    required this.nonCheckCauses,
    required this.intake,
    required this.tierOrder,
    required this.tierLabels,
    required this.serviceLabels,
  });

  Symptom symptom(String id) => symptoms.firstWhere((s) => s.id == id);

  /// Label for anything the engine can conclude: a check or a non-check cause.
  String causeLabel(String id) =>
      nonCheckCauses[id]?.label ?? checks[id]?.faultLabel ?? id;

  factory KnowledgeBase.fromJson(Map<String, dynamic> j) {
    final sections = <Section>[];
    final checks = <String, Check>{};
    for (final s in j['sections'] as List) {
      final list = [
        for (final c in s['checks'] as List) Check.fromJson(c, s['id'])
      ];
      for (final c in list) {
        checks[c.id] = c;
      }
      sections.add(Section(s['id'], s['label'], s['applies_if'], list));
    }

    final repairs = {
      for (final r in j['repairs'] as List)
        r['id'] as String: Repair(r['id'], r['label'],
            List<String>.from(r['parts'] ?? const []), r['per_position'] == true, r['note'])
    };

    final symptoms = [
      for (final s in j['symptoms'] as List)
        Symptom(
          id: s['id'],
          label: s['label'] ?? s['id'],
          customerPhrases: List<String>.from(s['customer_phrases'] ?? const []),
          isFullCheck: s['flow'] == 'full_mcheck',
          safetyCritical: s['safety_critical'] == true,
          candidates: {
            for (final e in (s['candidates'] as Map? ?? const {}).entries)
              e.key as String: (e.value as num).toDouble()
          },
          askOrder: List<String>.from(s['ask_order'] ?? const []),
          extraQuestions: [
            for (final q in s['extra_questions'] as List? ?? const [])
              ExtraQuestion(q['id'], q['ask'], [
                for (final o in q['options'] as List? ?? const [])
                  AnswerOption.fromJson(o)
              ])
          ],
          serviceUpsell: s['service_upsell'],
        )
    ];

    final nonCheck = {
      for (final e in (j['non_check_causes'] as Map? ?? const {}).entries)
        e.key as String: NonCheckCause(
          e.key,
          e.value['label'],
          List<String>.from(e.value['repairs'] ?? const []),
          e.value['diy_possible'] == true,
          _parseConfidence(e.value['remote_confidence']),
        )
    };

    final tiers = j['service_tiers'] as Map<String, dynamic>;
    final tierLabels = <String, String>{
      for (final e in tiers.entries)
        if (e.value is Map) e.key: e.value['label'] as String
    };

    return KnowledgeBase._(
      version: j['meta']['version'],
      sections: sections,
      checks: checks,
      repairs: repairs,
      symptoms: symptoms,
      nonCheckCauses: nonCheck,
      intake: [
        for (final q in j['intake_questions'] as List)
          IntakeQuestion(q['id'], q['ask'],
              List<String>.from(q['options'] ?? const []), q['photo'])
      ],
      tierOrder: List<String>.from(tiers['order']),
      tierLabels: tierLabels,
      serviceLabels: {
        for (final s in j['standalone_services'] as List)
          s['id'] as String: s['label'] as String
      },
    );
  }
}
