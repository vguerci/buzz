part of '../settings_page.dart';

/// Reports the four preconditions the push lease bootstrap waits on, and the
/// results it produces.
///
/// Push failures are otherwise invisible. The bridge records them in
/// `ValueNotifier`s that nothing reads, and the only other way to see them is a
/// device log, which needs a cable or a shared local network — neither of which
/// is available when the phone is the thing being debugged remotely.
class _PushSection extends HookConsumerWidget {
  const _PushSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    useListenable(apnsDeviceToken);
    useListenable(apnsRegistrationError);
    useListenable(pushEndpointGrants);
    useListenable(pushEndpointGrantError);
    useListenable(pushAuthorizationStatus);

    useEffect(() {
      unawaited(readBuzzPushAuthorizationStatus());
      return null;
    }, const []);

    final session = ref.watch(relaySessionProvider);
    final config = ref.watch(relayConfigProvider);
    final memberPubkey = ref.watch(myPubkeyProvider);

    final token = apnsDeviceToken.value;
    final registrationError = apnsRegistrationError.value;
    final grants = pushEndpointGrants.value;
    final grantError = pushEndpointGrantError.value;

    final sessionReady = session.status == SessionStatus.connected;
    final keyReady = (config.nsec ?? '').isNotEmpty;
    final pubkeyReady = memberPubkey != null;
    final tokenReady = token != null;
    final blocked = !sessionReady || !keyReady || !pubkeyReady || !tokenReady;

    return AppListCard(
      label: 'Push',
      children: [
        _PushRow(
          icon: LucideIcons.plug,
          title: 'Relay session',
          value: session.status.name,
          ok: sessionReady,
        ),
        _PushRow(
          icon: LucideIcons.key,
          title: 'Signing key',
          value: keyReady ? 'present' : 'missing',
          ok: keyReady,
        ),
        _PushRow(
          icon: LucideIcons.user,
          title: 'Member pubkey',
          value: pubkeyReady ? _short(memberPubkey) : 'missing',
          ok: pubkeyReady,
        ),
        _PushRow(
          icon: LucideIcons.bellRing,
          title: 'Notification permission',
          value: pushAuthorizationStatus.value ?? 'checking…',
          ok: pushAuthorizationStatus.value == 'authorized',
        ),
        _PushRow(
          icon: LucideIcons.bell,
          title: 'APNs token',
          value: token != null
              ? '${_short(token)} (${token.length ~/ 2} bytes)'
              : registrationError ?? 'not registered',
          ok: tokenReady,
        ),
        AppListRow(
          icon: LucideIcons.server,
          title: 'Push gateway',
          subtitle: Env.pushGatewayUrl,
        ),
        _PushRow(
          icon: LucideIcons.ticket,
          title: 'Endpoint grants',
          value: grants.isEmpty
              ? 'none'
              : '${grants.length} · ${grants.first.appProfile} · '
                    'gen ${grants.first.generation}'
                    '${grants.first.publishedGeneration == null ? ' (unpublished)' : ''}',
          ok: grants.isNotEmpty,
        ),
        if (grantError != null)
          AppListRow(
            icon: LucideIcons.triangleAlert,
            title: 'Last push error',
            titleColor: context.colors.error,
            subtitle: grantError,
          ),
        if (blocked && grantError == null)
          AppListRow(
            icon: LucideIcons.info,
            title: 'Enrollment has not run',
            subtitle:
                'It waits for the relay session, signing key, member pubkey, '
                'and APNs token together. The row above without a check is the '
                'one holding it up.',
          ),
        AppListRow(
          icon: LucideIcons.clipboard,
          title: 'Copy push diagnostics',
          onTap: () => unawaited(
            copyToClipboard(
              context,
              _diagnostics(
                session: session.status.name,
                authorization: pushAuthorizationStatus.value,
                keyReady: keyReady,
                memberPubkey: memberPubkey,
                token: token,
                registrationError: registrationError,
                grants: grants,
                grantError: grantError,
                relayUrl: config.baseUrl,
              ),
              message: 'Push diagnostics copied',
            ),
          ),
        ),
      ],
    );
  }
}

String _short(String value) =>
    value.length <= 12 ? value : '${value.substring(0, 12)}…';

String _diagnostics({
  required String session,
  required String? authorization,
  required bool keyReady,
  required String? memberPubkey,
  required String? token,
  required String? registrationError,
  required List<BuzzPushEndpointGrant> grants,
  required String? grantError,
  required String relayUrl,
}) {
  final buffer = StringBuffer()
    ..writeln('relay session: $session')
    ..writeln('relay url: $relayUrl')
    ..writeln('notification permission: ${authorization ?? 'unknown'}')
    ..writeln('signing key: ${keyReady ? 'present' : 'missing'}')
    ..writeln('member pubkey: ${memberPubkey ?? 'missing'}')
    ..writeln('apns token: ${token ?? 'none'}')
    ..writeln('apns error: ${registrationError ?? 'none'}')
    ..writeln('gateway: ${Env.pushGatewayUrl}')
    ..writeln('grants: ${grants.length}');
  for (final grant in grants) {
    buffer.writeln(
      '  ${grant.appProfile} origin=${grant.relayOrigin} '
      'gen=${grant.generation} published=${grant.publishedGeneration} '
      'expires=${grant.expiresAt}',
    );
  }
  buffer.writeln('last push error: ${grantError ?? 'none'}');
  return buffer.toString();
}

/// A row whose value doubles as a pass/fail marker, so the blocking
/// precondition is visible without reading every line.
class _PushRow extends StatelessWidget {
  const _PushRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.ok,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return AppListRow(
      icon: icon,
      title: title,
      subtitle: value,
      trailing: Icon(
        ok ? LucideIcons.check : LucideIcons.x,
        size: 18,
        color: ok ? context.colors.primary : context.colors.error,
      ),
    );
  }
}
