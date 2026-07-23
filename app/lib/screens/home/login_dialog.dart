import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/account_session.dart';
import '../../state/providers.dart';

/// Prompts for the account code + current TOTP code and, on success, stores
/// an in-memory [AccountSession]. Used whenever the app needs to view
/// history or manage devices — deliberately separate from device pairing,
/// which only happens once during onboarding.
Future<bool> showAccountLoginDialog(BuildContext context, WidgetRef ref) async {
  final codeController = TextEditingController();
  final totpController = TextEditingController();
  String? error;

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        Future<void> submit() async {
          final code = codeController.text.trim();
          final totp = totpController.text.trim();
          if (code.isEmpty || totp.length != 6) {
            setState(() => error = 'Enter your account code and current 6-digit code.');
            return;
          }
          try {
            final api = ref.read(apiClientProvider);
            final login = await api.login(code: code, totp: totp);
            ref.read(accountSessionProvider.notifier).state = AccountSession(
              sessionToken: login.sessionToken,
              saltBase64: login.saltBase64,
              code: code,
            );
            if (context.mounted) Navigator.of(context).pop(true);
          } catch (e) {
            setState(() => error = 'Login failed: $e');
          }
        }

        return AlertDialog(
          title: const Text('Log in'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeController,
                decoration: const InputDecoration(labelText: 'Account code'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: totpController,
                decoration: const InputDecoration(labelText: '6-digit code'),
                keyboardType: TextInputType.number,
                maxLength: 6,
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: submit, child: const Text('Log in')),
          ],
        );
      },
    ),
  );

  return result ?? false;
}
