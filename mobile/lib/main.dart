import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'shared/push/push_bridge.dart';
import 'shared/push/push_lease_bootstrap.dart';
import 'shared/theme/theme_provider.dart';

void main() => runBuzzApp(const PushLeaseBootstrap(child: App()));

Future<void> runBuzzApp(Widget app) async {
  WidgetsFlutterBinding.ensureInitialized();
  installBuzzPushMethodHandler();
  // Before the first frame, so the lease bootstrap and every descriptor check
  // agree with the profile the native enrollment request will actually send.
  await syncBuzzPushAppProfile();

  // Pre-load preferences so the first frame uses the saved theme/accent.
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [savedPrefsProvider.overrideWithValue(prefs)],
      child: app,
    ),
  );
}
