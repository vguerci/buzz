import 'package:buzz/features/settings/settings_page.dart';
import 'package:buzz/shared/community/community_membership_provider.dart';
import 'package:buzz/shared/push/push_bridge.dart';
import 'package:buzz/shared/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpSettings(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        savedPrefsProvider.overrideWithValue(prefs),
        currentCommunityRoleProvider.overrideWithValue(
          const AsyncData<CommunityMemberRole?>(null),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: SettingsPage(
          profileHeader: const SizedBox.shrink(),
          invitePageBuilder: (_) => const SizedBox.shrink(),
          identityRecoveryPageBuilder: (_) => const SizedBox.shrink(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    apnsDeviceToken.value = null;
    apnsRegistrationError.value = null;
    pushEndpointGrants.value = const [];
    pushEndpointGrantError.value = null;
    pushAuthorizationStatus.value = null;
  });

  tearDown(() {
    apnsDeviceToken.value = null;
    apnsRegistrationError.value = null;
    pushEndpointGrants.value = const [];
    pushEndpointGrantError.value = null;
    pushAuthorizationStatus.value = null;
  });

  testWidgets('names the precondition holding enrollment back', (tester) async {
    await _pumpSettings(tester);
    await tester.scrollUntilVisible(find.text('APNs token'), 200);

    expect(find.text('not registered'), findsOneWidget);
    expect(find.text('Enrollment has not run'), findsOneWidget);
  });

  testWidgets('surfaces the APNs registration error instead of a bare miss', (
    tester,
  ) async {
    apnsRegistrationError.value = 'no valid aps-environment entitlement';
    await _pumpSettings(tester);
    await tester.scrollUntilVisible(find.text('APNs token'), 200);

    expect(find.text('no valid aps-environment entitlement'), findsOneWidget);
    expect(find.text('not registered'), findsNothing);
  });

  testWidgets('shows a declined prompt as the cause of the missing token', (
    tester,
  ) async {
    pushAuthorizationStatus.value = 'denied';
    await _pumpSettings(tester);
    await tester.scrollUntilVisible(find.text('Notification permission'), 200);

    expect(find.text('denied'), findsOneWidget);
    // Without the permission row this reads as an unexplained absence.
    expect(find.text('not registered'), findsOneWidget);
  });

  testWidgets('reports a push failure that already has an error', (
    tester,
  ) async {
    pushEndpointGrantError.value = 'attestation rejected';
    await _pumpSettings(tester);
    await tester.scrollUntilVisible(find.text('Last push error'), 200);

    expect(find.text('attestation rejected'), findsOneWidget);
    // The generic hint would be noise next to a real error.
    expect(find.text('Enrollment has not run'), findsNothing);
  });
}
