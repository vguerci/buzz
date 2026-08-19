import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../features/channels/channel_push_pins/channel_push_pins_provider.dart';
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
    final pins = ref.watch(channelPushPinsProvider);
    final nsec = config.nsec;
    final deviceToken = apnsDeviceToken.value;
    // A lease is a snapshot of what the user wants woken for, so a changed pin
    // set is as much a reason to republish as a rotated APNs token. Enrolment
    // mints the next generation, which is what makes the replacement
    // acceptable to the executor.
    final pinnedChannels = pins.pinnedChannelIds;
    final pinKey = pinnedChannels.join(',');
    useEffect(() {
      final attemptKey = [
        session.status.name,
        config.baseUrl,
        nsec,
        memberPubkey,
        deviceToken,
        pinKey,
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
          // Record the reason rather than dropping it. Every step below can
          // throw — the NIP-11 descriptor fetch, the native enrollment, the
          // lease publish — and an unawaited future carries the error nowhere,
          // so a failed enrollment is indistinguishable from one that never
          // ran: no grant, no notification, and nothing on screen.
          unawaited(
            _publish(config, memberPubkey, relay, pinnedChannels).catchError((
              Object error,
              StackTrace stack,
            ) {
              pushEndpointGrantError.value = error.toString();
              debugPrint('Push lease bootstrap failed: $error');
              debugPrintStack(stackTrace: stack);
            }),
          );
        });
      }
      return null;
    }, [
      session.status,
      config.baseUrl,
      nsec,
      memberPubkey,
      deviceToken,
      pinKey,
    ]);
    return child;
  }

  Future<void> _publish(
    RelayConfig config,
    String memberPubkey,
    SignedEventRelay relay,
    List<String> pinnedChannels,
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
      pinnedChannels: pinnedChannels,
    );
    await markBuzzDevPushLeasePublished(grant);
  }
}
