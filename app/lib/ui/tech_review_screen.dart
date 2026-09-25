// Copyright (c) 2026 Raj Kumar G K. All rights reserved.
// Proprietary and confidential. See LICENSE in the project root.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_services.dart';
import '../data/session_store.dart';

/// Where a technician confirms or corrects what the app concluded, once the
/// bike has been seen in the workshop. This builds the labelled dataset.
class TechReviewScreen extends StatefulWidget {
  final AppServices services;
  const TechReviewScreen(this.services, {super.key});

  @override
  State<TechReviewScreen> createState() => _TechReviewScreenState();
}

class _TechReviewScreenState extends State<TechReviewScreen> {
  late Future<List<SessionRecord>> _sessions;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _sessions = widget.services.store.list();

  Future<void> _export() async {
    final json = await widget.services.store.exportAll();
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All sessions copied as JSON')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final kb = widget.services.kb;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tech review'),
        actions: [
          IconButton(
              tooltip: 'Export JSON',
              icon: const Icon(Icons.download_outlined),
              onPressed: _export),
        ],
      ),
      body: FutureBuilder<List<SessionRecord>>(
        future: _sessions,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!;
          if (list.isEmpty) {
            return const Center(child: Text('No assessments yet.'));
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final r = list[i];
              final a = r.assessment;
              final symptomId = a['symptom_id'] as String?;
              final bike = (a['bike'] as Map?)?['make_model'] ?? 'Unknown bike';
              return ListTile(
                leading: Icon(
                  r.reviewed ? Icons.verified : Icons.pending_outlined,
                  color: r.reviewed ? Theme.of(context).colorScheme.primary : null,
                ),
                title: Text(symptomId == null
                    ? 'Incomplete'
                    : kb.symptom(symptomId).label),
                subtitle: Text('$bike · ${_date(r.createdAt)}'),
                onTap: () async {
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => _ReviewDetail(widget.services, r)));
                  setState(_reload);
                },
              );
            },
          );
        },
      ),
    );
  }

  static String _date(DateTime d) =>
      '${d.day}/${d.month}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
}

class _ReviewDetail extends StatefulWidget {
  final AppServices services;
  final SessionRecord record;
  const _ReviewDetail(this.services, this.record);

  @override
  State<_ReviewDetail> createState() => _ReviewDetailState();
}

class _ReviewDetailState extends State<_ReviewDetail> {
  late final Set<String> _confirmed = {...widget.record.confirmedCauses};
  late final _notes = TextEditingController(text: widget.record.techNotes);

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final r = widget.record
      ..confirmedCauses = _confirmed.toList()
      ..techNotes = _notes.text
      ..reviewedAt = DateTime.now();
    await widget.services.store.save(r);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final kb = widget.services.kb;
    final theme = Theme.of(context);
    final a = widget.record.assessment;
    final turns = (a['turns'] as List? ?? const []).cast<Map>();
    final predicted = [
      for (final f in ((a['result'] as Map?)?['findings'] as List? ?? const []))
        (f as Map)['cause_id'] as String
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Confirm outcome')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('App suggested', style: theme.textTheme.titleMedium),
          if (predicted.isEmpty) const Text('No faults'),
          for (final id in predicted) Text('• ${kb.causeLabel(id)}'),
          const SizedBox(height: 16),
          ExpansionTile(
            title: const Text('Conversation'),
            tilePadding: EdgeInsets.zero,
            children: [
              for (final t in turns)
                ListTile(
                  dense: true,
                  title: Text(t['question'] ?? ''),
                  subtitle: Text([
                    t['free_text'] ?? t['value'],
                    if (t['photo_assessment'] != null)
                      'photo: ${t['photo_assessment']['verdict']} '
                          '(${t['photo_assessment']['observations']})',
                  ].join(' — ')),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text('What was actually wrong?', style: theme.textTheme.titleMedium),
          for (final section in kb.sections)
            ExpansionTile(
              title: Text(section.label),
              tilePadding: EdgeInsets.zero,
              initiallyExpanded:
                  section.checks.any((c) => predicted.contains(c.id)),
              children: [
                for (final c in section.checks)
                  CheckboxListTile(
                    dense: true,
                    value: _confirmed.contains(c.id),
                    title: Text(c.mcheckText),
                    onChanged: (v) => setState(() =>
                        v! ? _confirmed.add(c.id) : _confirmed.remove(c.id)),
                  ),
              ],
            ),
          for (final n in kb.nonCheckCauses.values)
            CheckboxListTile(
              dense: true,
              value: _confirmed.contains(n.id),
              title: Text(n.label),
              onChanged: (v) => setState(
                  () => v! ? _confirmed.add(n.id) : _confirmed.remove(n.id)),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notes (what the app missed or got wrong)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Save review')),
        ],
      ),
    );
  }
}
