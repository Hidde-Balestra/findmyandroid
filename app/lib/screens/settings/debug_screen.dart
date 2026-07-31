import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_settings.dart';
import '../../state/providers.dart';

/// Diagnostic tools for troubleshooting the security-snapshot feature, not
/// needed for normal use. The lock-screen trigger has several independent
/// failure points (Device Administrator not actually detecting the failed
/// attempt, vs. the background poll not picking up the pending flag, vs. the
/// upload itself failing) — this screen isolates the first of those from the
/// rest of that pipeline.
class DebugScreen extends ConsumerWidget {
  const DebugScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifyEnabled = ref.watch(debugLockscreenNotifyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Debug')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Diagnostic tools for troubleshooting the security-snapshot feature. '
              'Not needed for normal use.',
            ),
          ),
          SwitchListTile(
            title: const Text('Notify on failed lock-screen unlock'),
            subtitle: const Text(
              'Shows an immediate system notification the moment Android reports a failed '
              'lock-screen PIN/pattern/password attempt — independent of the security-snapshot '
              'threshold and the up-to-5-minute background poll. Use this to check whether '
              'Device Administrator is actually detecting failed attempts on this phone.',
            ),
            isThreeLine: true,
            value: notifyEnabled,
            onChanged: (value) => ref.read(debugLockscreenNotifyProvider.notifier).setEnabled(value),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: () => ref.read(deviceAdminBridgeProvider).sendTestNotification(),
              child: const Text('Send test notification'),
            ),
          ),
        ],
      ),
    );
  }
}
