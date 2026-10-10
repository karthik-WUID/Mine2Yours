import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_controller.dart';
import '../../core/design.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Brand(width: 220),
                const SizedBox(height: 24),
                const Text(
                  'Talk to your team',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const Text(
                  'No login needed. Connect to your team server to start.',
                ),
                if (state.error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(state.error!, textAlign: TextAlign.center),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => runAction(
                    context,
                    ref.read(appProvider.notifier).startWithoutLogin,
                  ),
                  child: const Text('Connect & continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
