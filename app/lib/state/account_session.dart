import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The interactive account session (from code + TOTP login), held in memory
/// only — deliberately never persisted to disk. Used to view location
/// history and manage/ring devices; separate from the per-device API token
/// the background check-in uses, which *is* persisted.
class AccountSession {
  final String sessionToken;
  final String saltBase64;
  final String code;

  const AccountSession({required this.sessionToken, required this.saltBase64, required this.code});
}

final accountSessionProvider = StateProvider<AccountSession?>((ref) => null);
