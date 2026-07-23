import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'background/location_worker.dart';
import 'screens/home/home_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'state/app_settings.dart';
import 'state/providers.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureBackgroundService(FlutterBackgroundService());
  runApp(const ProviderScope(child: FindMyAndroidApp()));
}

class FindMyAndroidApp extends ConsumerWidget {
  const FindMyAndroidApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Find My Android',
      themeMode: themeMode,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      home: const _StartupGate(),
    );
  }
}

/// Routes straight to the home screen if this phone is already paired,
/// otherwise into onboarding.
class _StartupGate extends ConsumerWidget {
  const _StartupGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPaired = ref.watch(isPairedProvider);

    return isPaired.when(
      data: (paired) => paired ? const HomeScreen() : const OnboardingScreen(),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) => const OnboardingScreen(),
    );
  }
}
