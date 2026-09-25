// Copyright (c) 2026 Raj Kumar G K. All rights reserved.
// Proprietary and confidential. See LICENSE in the project root.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_services.dart';
import '../engine/assessment_engine.dart';
import '../engine/estimate.dart';

class ResultScreen extends StatelessWidget {
  final AppServices services;
  final AssessmentResult result;
  final BikeProfile bike;
  const ResultScreen(this.services, this.result, this.bike, {super.key});

  String _money(double? v) => v == null ? 'Price on inspection' : services.shop.format(v);

  String _priceRange(double? lo, double? hi) {
    if (lo == null) return 'Price on inspection';
    if (hi == null || (hi - lo).abs() < 0.01) return _money(lo);
    return '${_money(lo)} – ${_money(hi)}';
  }

  String _summary(Estimate est) {
    final b = StringBuffer()
      ..writeln('Bike: ${bike.makeModel ?? 'not given'}'
          '${bike.isEbike ? ' (eBike)' : ''}, brakes: ${bike.brakeType}')
      ..writeln();
    if (result.stopRiding) b.writeln('!! Customer advised to stop riding until checked.\n');
    for (final l in est.lines) {
      b.writeln('- ${l.finding.label}');
      b.writeln('  Likely fix: ${l.repairLabel} '
          '(${l.includedAbove ? 'included above' : _priceRange(l.low, l.high)})');
    }
    for (final id in result.unsureChecks) {
      b.writeln('- Not sure: ${services.kb.checks[id]!.mcheckText}');
    }
    b.writeln('\nEstimate: ${_priceRange(est.low, est.high)}'
        '${est.hasUnpriced ? ' + items priced on inspection' : ''}');
    return b.toString();
  }

  Future<void> _requestBooking(BuildContext context, Estimate est) async {
    final email = services.shop.bookingEmail;
    final url = services.shop.bookingUrl;
    final Uri uri = url != null
        ? Uri.parse(url)
        : Uri(
            scheme: 'mailto',
            path: email,
            query: _encodeQuery({
              'subject': 'Repair booking request',
              'body': '${_summary(est)}\nPreferred date/time: \nName: \nPhone: ',
            }),
          );
    if (!await launchUrl(uri) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open booking. Please contact the shop.')));
    }
  }

  // mailto: needs %20 rather than '+', so encode manually.
  static String _encodeQuery(Map<String, String> params) => params.entries
      .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
      .join('&');

  Widget _card(Finding f, EstimateLine? line) {
    final kb = services.kb;
    return _FindingCard(
      finding: f,
      repairLine: line,
      priceText: (l) => _priceRange(l.low, l.high),
      alternatives: [
        for (final r in f.repairs)
          if ((kb.repairs[r]?.label ?? r) != line?.repairLabel)
            kb.repairs[r]?.label ?? r
      ],
      upsell: f.serviceUpsell == null ? null : kb.serviceLabels[f.serviceUpsell],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final kb = services.kb;
    final est = Estimate.build(result, kb, services.shop);

    return Scaffold(
      appBar: AppBar(title: const Text('Your assessment')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (result.cannotService)
                  _Banner(
                    color: cs.errorContainer,
                    fg: cs.onErrorContainer,
                    icon: Icons.block,
                    title: "We can't service this bike",
                    body: result.cannotServiceMessages.join('\n\n'),
                  ),
                if (result.stopRiding)
                  _Banner(
                    color: cs.errorContainer,
                    fg: cs.onErrorContainer,
                    icon: Icons.warning_amber_rounded,
                    title: 'Please stop riding until this is checked',
                    body: 'One or more safety-critical problems were reported. '
                        'Riding could be dangerous.',
                  ),
                if (result.findings.isEmpty && !result.cannotService)
                  _Banner(
                    color: cs.primaryContainer,
                    fg: cs.onPrimaryContainer,
                    icon: Icons.check_circle_outline,
                    title: 'No problems reported',
                    body: "Nothing you told us points to a fault. A technician's "
                        'hands-on check can still catch things that are hard to '
                        'spot at home.',
                  ),
                for (final f in result.findings)
                  _card(f, est.lines.where((l) => l.finding == f).firstOrNull),
                if (result.unsureChecks.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Worth a technician looking at',
                      style: theme.textTheme.titleMedium),
                  for (final id in result.unsureChecks)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.help_outline),
                      title: Text(kb.checks[id]!.faultLabel),
                    ),
                ],
                if (est.lines.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Estimated cost', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(_priceRange(est.low, est.high),
                              style: theme.textTheme.headlineMedium),
                          if (est.hasUnpriced)
                            const Text('+ some items priced on inspection'),
                          if (est.suggestedTier != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Tip: a ${kb.tierLabels[est.suggestedTier]} service '
                              'includes checking these items'
                              '${services.shop.tierPrices[est.suggestedTier] == null ? '' : ' (from ${_money(services.shop.tierPrices[est.suggestedTier])})'}.',
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            'Estimate from ${services.shop.name}'
                            '${services.shop.examplePrices ? ' (example prices)' : ''}. '
                            'Final price is confirmed after a technician inspects the bike.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (result.bookingNotes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final n in result.bookingNotes)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.info_outline),
                      title: Text(n),
                    ),
                ],
                const SizedBox(height: 16),
                if (!result.cannotService &&
                    (services.shop.bookingEmail != null ||
                        services.shop.bookingUrl != null))
                  FilledButton.icon(
                    icon: const Icon(Icons.event_available),
                    label: const Text('Request a booking'),
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16)),
                    onPressed: () => _requestBooking(context, est),
                  ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
                const SizedBox(height: 16),
                Text(
                  'This is a remote assessment, not an inspection. Some faults '
                  "can only be found hands-on. If you're unsure whether your "
                  'bike is safe, don\'t ride it until a technician has checked it.',
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final Color color, fg;
  final IconData icon;
  final String title, body;
  const _Banner(
      {required this.color,
      required this.fg,
      required this.icon,
      required this.title,
      required this.body});

  @override
  Widget build(BuildContext context) => Card(
        color: color,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: fg, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: fg)),
                    const SizedBox(height: 4),
                    Text(body, style: TextStyle(color: fg)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _FindingCard extends StatelessWidget {
  final Finding finding;
  final EstimateLine? repairLine;
  final String Function(EstimateLine) priceText;
  final List<String> alternatives;
  final String? upsell;

  const _FindingCard({
    required this.finding,
    required this.repairLine,
    required this.priceText,
    required this.alternatives,
    required this.upsell,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final f = finding;
    final (confLabel, confColor) = switch (f.confidence) {
      Confidence.high => ('High confidence', cs.primary),
      Confidence.medium => ('Likely', cs.tertiary),
      Confidence.low => ('Possible', cs.outline),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              _Tag(confLabel, confColor),
              if (f.safetyCritical) _Tag('Safety', cs.error),
              if (f.needsHandsOnCheck) _Tag('Needs hands-on check', cs.secondary),
              if (f.diyPossible) _Tag('DIY possible', cs.primary),
            ]),
            const SizedBox(height: 8),
            Text(f.label, style: theme.textTheme.titleMedium),
            if (f.message != null) ...[
              const SizedBox(height: 4),
              Text(f.message!),
            ],
            if (repairLine != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.build_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text(repairLine!.repairLabel)),
                Text(
                    repairLine!.includedAbove
                        ? 'Included above'
                        : priceText(repairLine!),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
            ],
            if (alternatives.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('May instead need: ${alternatives.join(', ')}',
                  style: theme.textTheme.bodySmall),
            ],
            if (f.products.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Suggested: ${f.products.map((p) => p.replaceAll('_', ' ')).join(', ')}'),
            ],
            if (upsell != null) ...[
              const SizedBox(height: 4),
              Text('Also consider: $upsell', style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}
