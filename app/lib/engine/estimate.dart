// Copyright (c) 2026 Raj Kumar G K. All rights reserved.
// Proprietary and confidential. See LICENSE in the project root.

/// Turns findings into a price estimate using a per-shop configuration.
library;

import '../kb/knowledge_base.dart';
import 'assessment_engine.dart';

class RepairPrice {
  final double? price; // fixed price, labour + parts
  final int? labourMinutes;
  final double? partsEstimate;
  const RepairPrice({this.price, this.labourMinutes, this.partsEstimate});

  factory RepairPrice.fromJson(Map<String, dynamic> j) => RepairPrice(
        price: (j['price'] as num?)?.toDouble(),
        labourMinutes: j['labour_minutes'] as int?,
        partsEstimate: (j['parts_estimate'] as num?)?.toDouble(),
      );
}

class ShopConfig {
  final String name;
  final String currency;
  final bool examplePrices;
  final String? bookingEmail;
  final String? bookingUrl;
  final double? labourRatePerHour;
  final Map<String, RepairPrice> repairs;
  final Map<String, double> tierPrices;

  const ShopConfig({
    required this.name,
    required this.currency,
    required this.examplePrices,
    required this.bookingEmail,
    required this.bookingUrl,
    required this.labourRatePerHour,
    required this.repairs,
    required this.tierPrices,
  });

  factory ShopConfig.fromJson(Map<String, dynamic> j) => ShopConfig(
        name: j['name'],
        currency: j['currency'] ?? '£',
        examplePrices: j['example_prices'] == true,
        bookingEmail: j['booking_email'],
        bookingUrl: j['booking_url'],
        labourRatePerHour: (j['labour_rate_per_hour'] as num?)?.toDouble(),
        repairs: {
          for (final e in (j['repairs'] as Map? ?? const {}).entries)
            e.key as String: RepairPrice.fromJson(e.value)
        },
        tierPrices: {
          for (final e in (j['service_tiers'] as Map? ?? const {}).entries)
            e.key as String: (e.value as num).toDouble()
        },
      );

  /// Price for one repair, or null if the shop hasn't priced it.
  double? priceFor(String repairId) {
    final r = repairs[repairId];
    if (r == null) return null;
    if (r.price != null) return r.price;
    if (r.labourMinutes == null || labourRatePerHour == null) return null;
    return r.labourMinutes! / 60 * labourRatePerHour! + (r.partsEstimate ?? 0);
  }

  String format(double v) => '$currency${v.toStringAsFixed(2)}';
}

class EstimateLine {
  final Finding finding;
  final String repairLabel;
  final double? low; // most likely repair
  final double? high; // most expensive of the possible repairs
  final bool includedAbove; // covered by a combined repair on another line
  const EstimateLine(this.finding, this.repairLabel, this.low, this.high,
      {this.includedAbove = false});
}

class Estimate {
  final List<EstimateLine> lines;
  final double low;
  final double high;
  final bool hasUnpriced;
  final String? suggestedTier;

  const Estimate(
      this.lines, this.low, this.high, this.hasUnpriced, this.suggestedTier);

  static Estimate build(AssessmentResult r, KnowledgeBase kb, ShopConfig shop) {
    final lines = <EstimateLine>[];
    var low = 0.0, high = 0.0;
    var unpriced = false;

    final priced = r.findings.where((f) => f.repairs.isNotEmpty).toList();
    final merged = <Finding>{};

    // Two faults fixed by one combined job (worn chain + worn cassette ->
    // "replace chain and cassette") are quoted once, as the combined job.
    for (var i = 0; i < priced.length; i++) {
      for (var j = i + 1; j < priced.length; j++) {
        final a = priced[i], b = priced[j];
        if (merged.contains(a) || merged.contains(b)) continue;
        final combined = _combinedRepair(a, b, kb);
        if (combined == null) continue;
        merged.addAll([a, b]);
        final price = shop.priceFor(combined);
        final label = kb.repairs[combined]!.label;
        if (price == null) unpriced = true;
        low += price ?? 0;
        high += price ?? 0;
        lines.add(EstimateLine(a, label, price, price));
        lines.add(EstimateLine(b, label, null, null, includedAbove: true));
      }
    }

    for (final f in priced) {
      if (merged.contains(f)) continue;
      final primary = f.repairs.first;
      final prices = f.repairs.map(shop.priceFor).toList();
      final lo = prices.first;
      final known = prices.whereType<double>();
      final hi = known.isEmpty ? null : known.reduce((a, b) => a > b ? a : b);
      if (lo == null) unpriced = true;
      low += lo ?? 0;
      high += hi ?? lo ?? 0;
      lines.add(EstimateLine(f, kb.repairs[primary]?.label ?? primary, lo, hi));
    }

    return Estimate(lines, low, high, unpriced, _suggestTier(r, kb));
  }

  /// A repair offered for both findings whose parts cover both of their
  /// most likely repairs.
  static String? _combinedRepair(Finding a, Finding b, KnowledgeBase kb) {
    Set<String> parts(String id) => kb.repairs[id]?.parts.toSet() ?? {};
    final needed = parts(a.repairs.first).union(parts(b.repairs.first));
    if (needed.isEmpty) return null;
    for (final id in a.repairs) {
      if (id == a.repairs.first || id == b.repairs.first) continue;
      if (b.repairs.contains(id) && parts(id).containsAll(needed)) return id;
    }
    return null;
  }

  /// Lowest service tier whose checks cover every tiered fault found.
  static String? _suggestTier(AssessmentResult r, KnowledgeBase kb) {
    var maxIndex = -1;
    for (final f in r.findings) {
      final i = f.tier == null ? -1 : kb.tierOrder.indexOf(f.tier!);
      if (i > maxIndex) maxIndex = i;
    }
    // A single small fault is better quoted as a repair than a service.
    if (maxIndex < 0 || r.findings.length < 2) return null;
    return kb.tierOrder[maxIndex];
  }
}
