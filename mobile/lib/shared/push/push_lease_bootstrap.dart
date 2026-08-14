import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../relay/relay_provider.dart';
import '../relay/relay_session.dart';
import '../relay/signed_event_relay.dart';
import 'dev_push_lease.dart';
import 'push_bridge.dart';

/// Enrols the device with the push gateway and publishes its `kind:30350`
/// lease once the relay session, signing key, and APNs token are all present.
///
/// This runs in every build, not only debug ones. Without it the app registers
/// for APNs and can receive a wake, but the relay has no lease to match, so
/// nothing is ever sent — which is what a TestFlight build did while this was
/// mounted only from a debug-only entry point.
class PushLeaseBootstrap extends HookConsumerWidget {
  final Widget child;

  const PushLeaseBootstrap({required this.child, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    useListenable(apnsDeviceToken);
    final attempted = useRef<String?>(null);
    final session = ref.watch(relaySessionProvider);
    final config = ref.watch(relayConfigProvider);
    final memberPubkey = ref.watch(myPubkeyProvider);
    final nsec = config.nsec;
    final deviceToken = apnsDeviceToken.value;
    useEffect(() {
      final attemptKey = [
        session.status.name,
        config.baseUrl,
        nsec,
        memberPubkey,
        deviceToken,
      ].join('|');
      if (session.status == SessionStatus.connected &&
          nsec != null &&
          memberPubkey != null &&
          deviceToken != null &&
          attempted.value != attemptKey) {
        attempted.value = attemptKey;
        final relay = SignedEventRelay(
          session: ref.read(relaySessionProvider.notifier),
          nsec: nsec,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_publish(config, memberPubkey, relay));
        });
      }
      return null;
    }, [session.status, config.baseUrl, nsec, memberPubkey, deviceToken]);
    return child;
  }

  Future<void> _publish(
    RelayConfig config,
    String memberPubkey,
    SignedEventRelay relay,
  ) async {
    final descriptor = await fetchBuzzPushLeaseDescriptor(config.baseUrl);
    final grant = await enrollBuzzDevPush(config.wsUrl, Env.pushGatewayUrl);
    if (grant.relayOrigin != descriptor.origin) {
      throw StateError(
        'Endpoint grant origin ${grant.relayOrigin} does not match descriptor origin ${descriptor.origin}',
      );
    }
    final publishedGeneration = grant.publishedGeneration;
    if (publishedGeneration == grant.generation) return;

    final nsec = config.nsec;
    if (nsec == null || nsec.isEmpty) {
      throw StateError('Cannot publish a push lease without a signing key');
    }
    await publishBuzzDevPushLeaseThroughRelay(
      grant: grant,
      descriptor: descriptor,
      nsec: nsec,
      memberPubkey: memberPubkey,
      relay: relay,
    );
    await markBuzzDevPushLeasePublished(grant);
  }
}
