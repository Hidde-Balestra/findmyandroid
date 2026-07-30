import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../background/location_worker.dart';
import '../../models/device.dart';
import '../../state/account_session.dart';
import '../../state/providers.dart';
import '../settings/settings_screen.dart';
import 'device_history_screen.dart';
import 'login_dialog.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _lastCheckIn;
  bool _loadingDevices = false;
  List<Device> _devices = [];

  @override
  void initState() {
    super.initState();
    _loadLastCheckIn();
  }

  Future<void> _loadLastCheckIn() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _lastCheckIn = prefs.getString(lastCheckInPrefsKey));
  }

  Future<void> _startReporting() async {
    final started = await startReportingIfPossible(ref);
    if (!mounted) return;
    if (!started) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission is required to start reporting.')),
      );
    }
  }

  Future<void> _testRingNow() async {
    final ringService = ref.read(ringServiceProvider);
    await ringService.init();
    await ringService.ringNow(
      title: 'Find My Android',
      body: 'Test sound',
      stopButtonLabel: 'Stop',
    );
  }

  Future<void> _manageDevices() async {
    final session = ref.read(accountSessionProvider);
    if (session == null) {
      final ok = await showAccountLoginDialog(context, ref);
      if (!ok) return;
    }
    setState(() => _loadingDevices = true);
    try {
      final newSession = ref.read(accountSessionProvider)!;
      final api = ref.read(apiClientProvider);
      final devices = await api.listDevices(newSession.sessionToken);
      setState(() => _devices = devices);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load devices: $e')));
    } finally {
      if (mounted) setState(() => _loadingDevices = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPaired = ref.watch(isPairedProvider).valueOrNull ?? false;
    final isReporting = ref.watch(isReportingProvider).valueOrNull ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Find My Android'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isReporting ? Icons.check_circle : Icons.error,
                        color: isReporting ? Colors.green : Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        !isPaired
                            ? 'Not paired'
                            : isReporting
                                ? 'This phone is reporting its location'
                                : 'Paired, but not reporting yet',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(_lastCheckIn ?? 'No check-in yet.'),
                  const SizedBox(height: 4),
                  if (isPaired && !isReporting)
                    FilledButton(
                      onPressed: _startReporting,
                      child: const Text('Start reporting'),
                    )
                  else
                    TextButton(onPressed: _loadLastCheckIn, child: const Text('Refresh status')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _testRingNow,
            icon: const Icon(Icons.volume_up),
            label: const Text('Play sound now (test)'),
          ),
          const SizedBox(height: 24),
          Text('Your devices', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_devices.isEmpty)
            FilledButton(
              onPressed: _loadingDevices ? null : _manageDevices,
              child: _loadingDevices
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Log in to view devices & history'),
            )
          else
            ..._devices.map(
              (device) => Card(
                child: ListTile(
                  title: Text(device.label),
                  subtitle: Text(device.lastSeenAt != null ? 'Last seen: ${device.lastSeenAt!.toLocal()}' : 'Never seen'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => DeviceHistoryScreen(device: device)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
