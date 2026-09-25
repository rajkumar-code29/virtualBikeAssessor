// Copyright (c) 2026 Raj Kumar G K. All rights reserved.
// Proprietary and confidential. See LICENSE in the project root.

import 'dart:convert';
import 'dart:io';

import 'package:bike_assessor/engine/assessment_engine.dart';
import 'package:bike_assessor/engine/estimate.dart';
import 'package:bike_assessor/kb/knowledge_base.dart';
import 'package:flutter_test/flutter_test.dart';

late KnowledgeBase kb;
late ShopConfig shop;

/// Answers intake: no make/model, given eBike / brakes / suspension, then the reason.
AssessmentEngine startWith(String symptomId,
    {bool ebike = false, String brakes = 'rim', String suspension = 'none'}) {
  final e = AssessmentEngine(kb);
  e.submit('skip');
  e.submit(ebike ? 'yes' : 'no');
  e.submit(brakes);
  e.submit(suspension);
  e.submit(symptomId);
  return e;
}

void main() {
  setUpAll(() {
    kb = KnowledgeBase.fromJson(
        jsonDecode(File('assets/kb/mcheck_kb.json').readAsStringSync()));
    shop = ShopConfig.fromJson(
        jsonDecode(File('assets/config/shop_config.json').readAsStringSync()));
  });

  group('knowledge base integrity', () {
    test('counts match the M-check form', () {
      expect(kb.checks.length, 36);
      expect(kb.symptoms.length, 13);
    });

    test('every reference resolves', () {
      for (final c in kb.checks.values) {
        for (final r in c.onFail.repairs) {
          expect(kb.repairs, contains(r), reason: '${c.id} -> $r');
        }
      }
      for (final s in kb.symptoms) {
        for (final id in [...s.candidates.keys, ...s.askOrder]) {
          expect(kb.checks.containsKey(id) || kb.nonCheckCauses.containsKey(id),
              isTrue,
              reason: '${s.id} -> $id');
        }
      }
    });

    test('every repair has a shop price', () {
      for (final id in kb.repairs.keys) {
        expect(shop.priceFor(id), isNotNull, reason: id);
      }
    });
  });

  group('intake', () {
    test('asks the intake questions in order, then routes', () {
      final e = AssessmentEngine(kb);
      expect(e.current!.id, 'bike_make_model');
      e.submit('text', freeText: 'Carrera Vengeance');
      expect(e.profile.makeModel, 'Carrera Vengeance');
      expect(e.current!.id, 'is_ebike');
      e.submit('no');
      e.submit('hydraulic_disc');
      e.submit('front');
      expect(e.current!.kind, PromptKind.reason);
      expect(e.current!.options.map((o) => o.value), isNot(contains('ebike_problem')));
    });
  });

  group('symptom flow', () {
    test('gears slipping: worn chain confirmed', () {
      final e = startWith('gears_slipping');
      expect(e.current!.id, 'chain_wear'); // highest prior asked first
      e.submit('problem');
      // Keeps asking while other causes remain plausible, then stops.
      var guard = 0;
      while (!e.isDone && guard++ < 10) {
        e.submit('ok');
      }
      expect(e.isDone, isTrue);
      final r = e.result();
      expect(r.findings.map((f) => f.causeId), ['chain_wear']);
      // Chain wear can't be confirmed by a photo or a customer.
      expect(r.findings.single.needsHandsOnCheck, isTrue);
      expect(r.findings.single.confidence, Confidence.low);
    });

    test('safety-critical candidates are always asked', () {
      final e = startWith('brakes_weak', brakes: 'rim');
      final asked = <String>[];
      while (!e.isDone) {
        asked.add(e.current!.id);
        e.submit('ok');
      }
      // hydraulic_brake does not apply to rim brakes; the others are safety-critical.
      expect(asked, containsAll(['brakes_stop_wheel', 'brake_pads']));
      expect(asked, isNot(contains('hydraulic_brake')));
    });

    test('brake failure tells the customer to stop riding', () {
      final e = startWith('brakes_weak', brakes: 'rim');
      e.submit('problem'); // brakes_stop_wheel
      while (!e.isDone) {
        e.submit('unsure');
      }
      final r = e.result();
      expect(r.stopRiding, isTrue);
      expect(r.findings.first.causeId, 'brakes_stop_wheel');
    });

    test('wheel wobble: extra question can confirm a non-check cause', () {
      final e = startWith('wheel_wobble');
      final seen = <String>[];
      while (!e.isDone) {
        final p = e.current!;
        seen.add(p.id);
        if (p.id == 'tyre_not_seated') {
          e.submit('uneven');
        } else {
          e.submit('ok');
        }
      }
      expect(seen, contains('tyre_not_seated'));
      final r = e.result();
      expect(r.findings.map((f) => f.causeId), contains('tyre_not_seated'));
      expect(r.findings.first.repairs, ['tyre_reseat']);
    });

    test('nothing confirmed -> most likely causes flagged for hands-on check', () {
      final e = startWith('gears_not_shifting');
      while (!e.isDone) {
        e.submit('unsure');
      }
      final r = e.result();
      expect(r.findings, isNotEmpty);
      expect(r.findings.every((f) => !f.confirmedByUser && f.needsHandsOnCheck),
          isTrue);
      expect(r.unsureChecks, isNotEmpty);
    });
  });

  group('full check', () {
    test('runs safety-critical checks first and skips non-applicable ones', () {
      final e = startWith('general_check', brakes: 'hydraulic_disc');
      final asked = <String>[];
      while (!e.isDone) {
        asked.add(e.current!.id);
        e.submit('ok');
      }
      final firstNonSafety =
          asked.indexWhere((id) => !kb.checks[id]!.safetyCritical);
      expect(asked.skip(firstNonSafety).where((id) => kb.checks[id]!.safetyCritical),
          isEmpty);
      expect(asked, isNot(contains('brakes_stop_wheel'))); // cable brakes only
      expect(asked, isNot(contains('suspension')));
      expect(asked, isNot(contains('ebike_display')));
      expect(e.result().findings, isEmpty);
    });

    test('ineligible eBike stops the assessment', () {
      final e = startWith('general_check', ebike: true);
      expect(e.current!.id, 'ebike_brand_approved');
      e.submit('ok');
      e.submit('problem'); // not EAPC compliant
      expect(e.isDone, isTrue);
      final r = e.result();
      expect(r.cannotService, isTrue);
      expect(r.findings, isEmpty);
    });
  });

  group('estimate', () {
    test('sums the most likely repair and the dearest alternative', () {
      final e = startWith('general_check', brakes: 'hydraulic_disc');
      while (!e.isDone) {
        final id = e.current!.id;
        e.submit(id == 'tyre_condition' || id == 'chain_wear' ? 'problem' : 'ok');
      }
      final est = Estimate.build(e.result(), kb, shop);
      expect(est.lines.length, 2);
      // tyre_replace 20min + £25 parts at £40/h = £38.33; chain_replace = £30.00
      expect(est.low, closeTo(38.33 + 30.0, 0.01));
      expect(est.high, greaterThan(est.low)); // chain + cassette is dearer
      expect(est.suggestedTier, 'gold');
    });

    test('worn chain + worn cassette are quoted as one combined job', () {
      final e = startWith('gears_slipping');
      while (!e.isDone) {
        final id = e.current!.id;
        e.submit(id == 'chain_wear' || id == 'chainring_cassette' ? 'problem' : 'ok');
      }
      final est = Estimate.build(e.result(), kb, shop);
      expect(est.lines.map((l) => l.repairLabel).toSet(),
          {'Replace chain and cassette/freewheel'});
      expect(est.lines.where((l) => l.includedAbove).length, 1);
      // 30 min at £40/h + £50 parts, counted once
      expect(est.low, closeTo(70.0, 0.01));
      expect(est.high, closeTo(70.0, 0.01));
    });

    test('findings use customer-facing fault names', () {
      final e = startWith('gears_slipping');
      e.submit('problem'); // chain_wear
      while (!e.isDone) {
        e.submit('ok');
      }
      expect(e.result().findings.single.label, 'Worn chain');
    });
  });
}
