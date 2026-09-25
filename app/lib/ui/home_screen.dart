// Copyright (c) 2026 Raj Kumar G K. All rights reserved.
// Proprietary and confidential. See LICENSE in the project root.

import 'package:flutter/material.dart';

import '../app_services.dart';
import 'chat_screen.dart';
import 'tech_review_screen.dart';

class HomeScreen extends StatelessWidget {
  final AppServices services;
  const HomeScreen(this.services, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Virtual Bike Assessor'),
        actions: [
          IconButton(
            tooltip: 'Tech review',
            icon: const Icon(Icons.build_circle_outlined),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => TechReviewScreen(services))),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Icon(Icons.pedal_bike, size: 72, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text('Is something wrong with your bike?',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall),
                const SizedBox(height: 12),
                Text(
                  "Answer a few questions and try some quick checks. "
                  "We'll tell you what's likely wrong, what it should cost, "
                  "and whether it's safe to ride.",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('Start assessment'),
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ChatScreen(services))),
                ),
                const SizedBox(height: 32),
                Text(
                  'Based on the ${services.kb.checks.length}-point M-check '
                  '· KB v${services.kb.version}\n'
                  '© 2026 Raj Kumar G K. All rights reserved.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
