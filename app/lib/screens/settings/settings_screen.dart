import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants.dart';
import '../../services/permission_service.dart';
import '../../services/security_capture_service.dart';
import '../../services/update_service.dart';
import '../../state/app_settings.dart';
import '../../state/providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> with WidgetsBindingObserver {
  Map<ReliabilityPermission, bool> _permissionStatus = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPermissions();
  }

  Future<void> _refreshPermissions() async {
    final status = await ref.read(permissionServiceProvider).statusSnapshot();
    if (mounted) setState(() => _permissionStatus = status);

    // Best-effort: if location permission just got granted here (rather than
    // during onboarding) and this phone is paired but not yet reporting,
    // start the service now instead of making the user find the "Start
    // reporting" button on Home themselves. Never lets a failure here (e.g.
    // secure storage unavailable) break the rest of the settings screen.
    try {
      final isPaired = await ref.read(secureStoreProvider).isPaired;
      if (isPaired && (status[ReliabilityPermission.location] ?? false)) {
        final service = ref.read(backgroundServiceProvider);
        if (!await service.isRunning()) await service.startService();
      }
    } catch (_) {
      // Ignored: Home's "Start reporting" button remains as a fallback.
    }
  }

  Future<void> _forgetDevice() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forget this device?'),
        content: const Text(
          'This stops location reporting from this phone and deletes its '
          'cached encryption key. Your account and any location history '
          'already on the server are unaffected.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Forget device')),
        ],
      ),
    );
    if (confirmed != true) return;

    ref.read(backgroundServiceProvider).invoke('stopService');
    await ref.read(secureStoreProvider).clear();
    ref.read(pairingRefreshProvider.notifier).state++;

    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader(title: 'Appearance'),
          RadioGroup<ThemeMode>(
            groupValue: themeMode,
            onChanged: (value) => ref.read(themeModeProvider.notifier).setThemeMode(value ?? themeMode),
            child: const Column(
              children: [
                RadioListTile<ThemeMode>(title: Text('System'), value: ThemeMode.system),
                RadioListTile<ThemeMode>(title: Text('Light'), value: ThemeMode.light),
                RadioListTile<ThemeMode>(title: Text('Dark'), value: ThemeMode.dark),
              ],
            ),
          ),
          const Divider(),
          _SectionHeader(
            title: 'Reporting',
            subtitle: 'Location is checked in every ${reportingInterval.inMinutes} minutes '
                'while this phone is paired, using a persistent foreground service '
                '(not Google Play Services).',
          ),
          ListTile(
            leading: const Icon(Icons.smartphone_outlined),
            title: const Text('Forget this device'),
            subtitle: const Text('Stops reporting and deletes the local encryption key'),
            onTap: _forgetDevice,
          ),
          const Divider(),
          const _SectionHeader(
            title: 'Permissions',
            subtitle: 'All of these are needed for reliable check-ins and for "play sound" '
                'to actually ring through Do Not Disturb.',
          ),
          _PermissionTile(
            title: 'Location',
            description: 'Needed to read this phone\'s GPS/network position.',
            permission: ReliabilityPermission.location,
            granted: _permissionStatus[ReliabilityPermission.location] ?? false,
            onRefresh: _refreshPermissions,
          ),
          _PermissionTile(
            title: 'Background location',
            description: 'Needed so check-ins keep working while the app is closed.',
            permission: ReliabilityPermission.backgroundLocation,
            granted: _permissionStatus[ReliabilityPermission.backgroundLocation] ?? false,
            onRefresh: _refreshPermissions,
          ),
          _PermissionTile(
            title: 'Notifications',
            description: 'Required to show the ongoing reporting notification.',
            permission: ReliabilityPermission.notification,
            granted: _permissionStatus[ReliabilityPermission.notification] ?? false,
            onRefresh: _refreshPermissions,
          ),
          _PermissionTile(
            title: 'Alarms & reminders',
            description: 'Lets the "play sound" alarm engine schedule reliably.',
            permission: ReliabilityPermission.exactAlarm,
            granted: _permissionStatus[ReliabilityPermission.exactAlarm] ?? false,
            onRefresh: _refreshPermissions,
          ),
          _PermissionTile(
            title: 'Do Not Disturb access',
            description: 'Extra reliability layer so "play sound" is never silenced.',
            permission: ReliabilityPermission.doNotDisturb,
            granted: _permissionStatus[ReliabilityPermission.doNotDisturb] ?? false,
            onRefresh: _refreshPermissions,
          ),
          _PermissionTile(
            title: 'Ignore battery optimization',
            description: 'Prevents the OS from killing the check-in service to save power.',
            permission: ReliabilityPermission.batteryOptimization,
            granted: _permissionStatus[ReliabilityPermission.batteryOptimization] ?? false,
            onRefresh: _refreshPermissions,
          ),
          _PermissionTile(
            title: 'Full-screen alerts',
            description: 'Android 14+: lets "play sound" take over the screen, incl. over the lock screen.',
            permission: ReliabilityPermission.fullScreenAlarm,
            granted: _permissionStatus[ReliabilityPermission.fullScreenAlarm] ?? false,
            onRefresh: _refreshPermissions,
          ),
          const Divider(),
          const _SectionHeader(
            title: 'Security snapshot',
            subtitle: 'After this many failed attempts — either the in-app account-code/6-digit-code '
                'login, or (if enabled below) this phone\'s own lock-screen PIN/pattern/password — it '
                'takes a front-camera photo and logs the current location as a security event, viewable '
                'later under this device\'s history. Set to Off to disable.',
          ),
          _PermissionTile(
            title: 'Camera',
            description: 'Required for the security snapshot above; has no other use in this app.',
            permission: ReliabilityPermission.camera,
            granted: _permissionStatus[ReliabilityPermission.camera] ?? false,
            onRefresh: _refreshPermissions,
          ),
          _PermissionTile(
            title: 'Device administrator',
            description: 'Optional: also triggers the security snapshot after too many failed '
                'lock-screen unlock attempts, not just failed in-app logins. Android will show its own '
                'prominent warning listing everything a device administrator app can do (e.g. wipe '
                'data) — this app only ever uses the failed-unlock notification.',
            permission: ReliabilityPermission.deviceAdmin,
            granted: _permissionStatus[ReliabilityPermission.deviceAdmin] ?? false,
            onRefresh: _refreshPermissions,
          ),
          const _SecuritySnapshotThresholdTile(),
          const _SecuritySnapshotStatusTile(),
          const Divider(),
          const _SectionHeader(title: 'Updates'),
          const _UpdatesSection(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _UpdatesSection extends ConsumerStatefulWidget {
  const _UpdatesSection();

  @override
  ConsumerState<_UpdatesSection> createState() => _UpdatesSectionState();
}

class _UpdatesSectionState extends ConsumerState<_UpdatesSection> {
  String? _currentVersion;
  UpdateCheckResult? _result;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  Future<void> _check() async {
    if (!_checking) setState(() => _checking = true);
    final info = await PackageInfo.fromPlatform();
    final result = await ref.read(updateServiceProvider).checkForUpdate(info.version);
    if (!mounted) return;
    setState(() {
      _currentVersion = info.version;
      _result = result;
      _checking = false;
    });
  }

  String get _statusText {
    if (_checking) return 'Checking for updates…';
    switch (_result?.status) {
      case UpdateStatus.updateAvailable:
        return 'Update available: v${_result!.latestVersion}';
      case UpdateStatus.upToDate:
        return 'You\'re up to date';
      case UpdateStatus.checkFailed:
      case null:
        return 'Could not check for updates';
    }
  }

  @override
  Widget build(BuildContext context) {
    final releaseUrl = _result?.releaseUrl;
    final showViewRelease = _result?.status == UpdateStatus.updateAvailable && releaseUrl != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_currentVersion != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Installed version: $_currentVersion', style: Theme.of(context).textTheme.bodySmall),
          ),
        ListTile(
          title: Text(_statusText),
          trailing: _checking
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : showViewRelease
                  ? FilledButton(
                      onPressed: () => ref.read(updateServiceProvider).openReleasePage(releaseUrl),
                      child: const Text('View release'),
                    )
                  : TextButton(onPressed: _check, child: const Text('Check now')),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _SectionHeader({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
          if (subtitle != null) Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _SecuritySnapshotThresholdTile extends ConsumerWidget {
  const _SecuritySnapshotThresholdTile();

  static const _options = [0, 1, 3, 5];

  String _label(int value) => value == 0 ? 'Off' : '$value failed attempt${value == 1 ? '' : 's'}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threshold = ref.watch(securitySnapshotThresholdProvider);
    return ListTile(
      title: const Text('Trigger after'),
      trailing: DropdownButton<int>(
        value: _options.contains(threshold) ? threshold : 1,
        items: [
          for (final value in _options) DropdownMenuItem(value: value, child: Text(_label(value))),
        ],
        onChanged: (value) {
          if (value != null) ref.read(securitySnapshotThresholdProvider.notifier).setThreshold(value);
        },
      ),
    );
  }
}

/// Shows the outcome of the last capture attempt — captureAndUpload() never
/// throws or otherwise reports failures to its caller by design, so without
/// this the feature would look like a silent black box with no way to tell
/// whether it actually did anything.
class _SecuritySnapshotStatusTile extends StatefulWidget {
  const _SecuritySnapshotStatusTile();

  @override
  State<_SecuritySnapshotStatusTile> createState() => _SecuritySnapshotStatusTileState();
}

class _SecuritySnapshotStatusTileState extends State<_SecuritySnapshotStatusTile> {
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _status = prefs.getString(lastSecuritySnapshotStatusPrefsKey));
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: const Text('Last snapshot attempt'),
      subtitle: Text(_status ?? 'None yet — nothing has triggered the threshold on this phone.'),
      isThreeLine: true,
      trailing: IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
    );
  }
}

class _PermissionTile extends ConsumerWidget {
  final String title;
  final String description;
  final ReliabilityPermission permission;
  final bool granted;
  final VoidCallback onRefresh;

  const _PermissionTile({
    required this.title,
    required this.description,
    required this.permission,
    required this.granted,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(title),
      subtitle: Text(description),
      isThreeLine: true,
      trailing: granted
          ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
          : TextButton(
              onPressed: () async {
                await ref.read(permissionServiceProvider).request(permission);
                onRefresh();
              },
              child: const Text('Open settings'),
            ),
    );
  }
}
