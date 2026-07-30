import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/api_client.dart';
import '../../state/providers.dart';
import '../home/home_screen.dart';

enum _Step { welcome, showNewCode, enterCode, pairing }

/// First-run flow. Either creates a brand-new, fully anonymous account (no
/// email/phone anywhere) and shows its one-time recovery code + TOTP QR, or
/// pairs this phone to an account created elsewhere by entering that code.
/// Either way it ends by deriving the location-encryption key locally,
/// pairing this device, and starting the 5-minute background check-in.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  _Step _step = _Step.welcome;
  RegisterResult? _registered;
  bool _savedConfirmed = false;
  bool _busy = false;
  String? _error;

  final _codeController = TextEditingController();
  final _totpController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    _totpController.dispose();
    super.dispose();
  }

  Future<void> _startNewAccount() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final result = await api.register();
      setState(() {
        _registered = result;
        _codeController.text = result.code;
        _step = _Step.showNewCode;
      });
    } catch (e) {
      setState(() => _error = 'Could not reach the server: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _completePairing() async {
    final code = _codeController.text.trim();
    final totp = _totpController.text.trim();
    if (code.isEmpty || totp.length != 6) {
      setState(() => _error = 'Enter your account code and the current 6-digit code.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _step = _Step.pairing;
    });

    try {
      final api = ref.read(apiClientProvider);
      final login = await api.login(code: code, totp: totp);
      final pairing = await api.pairDevice(sessionToken: login.sessionToken, label: 'This phone');

      final crypto = ref.read(cryptoServiceProvider);
      final key = await crypto.deriveKey(code: code, saltBase64: login.saltBase64);
      final keyBytes = await crypto.keyBytes(key);

      final store = ref.read(secureStoreProvider);
      await store.savePairing(
        deviceId: pairing.deviceId,
        deviceToken: pairing.deviceToken,
        accountSalt: login.saltBase64,
        lekBytes: keyBytes,
      );

      final service = ref.read(backgroundServiceProvider);
      await service.startService();

      ref.read(pairingRefreshProvider.notifier).state++;

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      setState(() {
        _error = 'Pairing failed: $e';
        _step = _Step.enterCode;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find My Android — Setup')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: switch (_step) {
            _Step.welcome => _buildWelcome(),
            _Step.showNewCode => _buildShowNewCode(),
            _Step.enterCode => _buildEnterCode(),
            _Step.pairing => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    );
  }

  Widget _buildWelcome() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Find My Android',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        const Text(
          'No Google Play Services. No email or phone number ever stored. '
          'Your location is end-to-end encrypted — the server only ever sees '
          'unreadable ciphertext.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        if (_error != null) ...[
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 16),
        ],
        FilledButton(
          onPressed: _busy ? null : _startNewAccount,
          child: const Text('Create a new account'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _busy ? null : () => setState(() => _step = _Step.enterCode),
          child: const Text('I already have an account code'),
        ),
      ],
    );
  }

  Widget _buildShowNewCode() {
    final result = _registered!;
    return ListView(
      children: [
        Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'This code is shown only once and cannot be recovered. '
              'Store it in your password manager now. Anyone with this code '
              'and your authenticator can see this account\'s location — '
              'keep it as secret as a password.',
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Your account code', style: TextStyle(fontWeight: FontWeight.bold)),
        SelectableText(
          result.code,
          style: const TextStyle(fontSize: 20, fontFeatures: [FontFeature.tabularFigures()]),
        ),
        const SizedBox(height: 24),
        const Text(
          'Set up the second factor in an authenticator app (e.g. Aegis, FreeOTP) — '
          'scan the QR code below, or type this secret in by hand if it can\'t scan:',
        ),
        const SizedBox(height: 8),
        SelectableText(
          result.totpSecret,
          style: const TextStyle(fontSize: 18, fontFeatures: [FontFeature.tabularFigures()]),
        ),
        const SizedBox(height: 12),
        Center(
          child: QrImageView(
            data: result.totpProvisioningUri,
            size: 200,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 24),
        CheckboxListTile(
          value: _savedConfirmed,
          onChanged: (value) => setState(() => _savedConfirmed = value ?? false),
          title: const Text('I have saved this code in my password manager'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _savedConfirmed ? () => setState(() => _step = _Step.enterCode) : null,
          child: const Text('Continue'),
        ),
      ],
    );
  }

  Widget _buildEnterCode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Enter your account code and current 6-digit code to pair this phone.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _codeController,
          decoration: const InputDecoration(labelText: 'Account code', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _totpController,
          decoration: const InputDecoration(labelText: '6-digit code', border: OutlineInputBorder()),
          keyboardType: TextInputType.number,
          maxLength: 6,
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy ? null : _completePairing,
          child: const Text('Pair this phone'),
        ),
      ],
    );
  }
}
