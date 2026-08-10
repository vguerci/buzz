import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/relay/relay.dart';

/// In-memory cache of other users' presence.
///
/// Two sources feed the cache:
///
/// * a one-shot `POST /query` seed for kind:20001, issued whenever pubkeys
///   start being tracked and again after every reconnect — without it the
///   cache stays empty until a peer happens to republish, so everyone renders
///   offline on launch;
/// * a kind:20001 subscription over the relay WebSocket for live updates.
///
/// TTL expiry will be handled by the relay-side `presence:true` filter
/// extension when that lands.
class PresenceCacheNotifier extends Notifier<Map<String, String>> {
  static const _presenceStatuses = {'online', 'away', 'offline'};

  /// Widgets track one pubkey each as they mount, so seeds are batched over a
  /// frame instead of firing one request per row.
  static const _seedBatchWindow = Duration(milliseconds: 16);

  final Set<String> _tracked = {};
  final Set<String> _pendingSeed = {};
  Timer? _seedTimer;
  void Function()? _presenceUnsub;
  int _subscriptionVersion = 0;
  int _generation = 0;

  @override
  Map<String, String> build() {
    final sessionState = ref.watch(relaySessionProvider);
    // Invalidates seeds still in flight from a previous connection, whose
    // results describe the state this build() just cleared.
    _generation++;

    ref.onDispose(() {
      _seedTimer?.cancel();
      _seedTimer = null;
      _presenceUnsub?.call();
      _presenceUnsub = null;
    });

    if (sessionState.status == SessionStatus.connected) {
      _subscribePresenceUpdates();
      // build() re-fires — and resets state to {} — on every reconnect, so the
      // seed has to run from here too, not only from track().
      _queueSeed(_tracked);
    }

    return {};
  }

  /// Track presence for [pubkeys].
  ///
  /// Newly tracked pubkeys are seeded from the relay immediately; the tracked
  /// set also filters incoming events so the cache doesn't grow unbounded.
  void track(List<String> pubkeys) {
    final normalized = pubkeys.map((pk) => pk.toLowerCase()).toList();
    final fresh = normalized.where((pk) => !_tracked.contains(pk)).toSet();
    _tracked.addAll(normalized);
    if (fresh.isEmpty) return;
    if (ref.read(relaySessionProvider).status != SessionStatus.connected) {
      // Not connected yet — build() seeds the whole tracked set on connect.
      return;
    }
    _queueSeed(fresh);
  }

  /// Collect [pubkeys] into the next batched seed.
  void _queueSeed(Set<String> pubkeys) {
    if (pubkeys.isEmpty) return;
    _pendingSeed.addAll(pubkeys);
    _seedTimer?.cancel();
    _seedTimer = Timer(_seedBatchWindow, _seedPresence);
  }

  /// Fetch the latest known presence for the queued pubkeys in one query.
  ///
  /// Relay-synthesized presence events carry the subject in a `p` tag while
  /// self-signed ones use the event author, so both are resolved. Failure is
  /// non-fatal — live events still populate the cache.
  Future<void> _seedPresence() async {
    _seedTimer = null;
    if (_pendingSeed.isEmpty) return;
    final authors = _pendingSeed.toList();
    _pendingSeed.clear();
    final generation = _generation;

    final session = ref.read(relaySessionProvider.notifier);
    List<NostrEvent> events;
    try {
      events = await session.queryRelay([
        NostrFilter(
          kinds: const [EventKind.presenceUpdate],
          authors: authors,
          limit: authors.length,
        ),
      ]);
    } catch (error) {
      debugPrint('[PresenceCacheNotifier] presence seed failed: $error');
      return;
    }

    // A reconnect cleared the state this response describes.
    if (generation != _generation) return;

    final latest = <String, ({int createdAt, String status})>{};
    for (final event in events) {
      final pubkey = _subjectPubkey(event);
      if (!_tracked.contains(pubkey)) continue;
      final status = event.content.trim();
      if (!_presenceStatuses.contains(status)) continue;
      final previous = latest[pubkey];
      if (previous != null && previous.createdAt >= event.createdAt) continue;
      latest[pubkey] = (createdAt: event.createdAt, status: status);
    }
    if (latest.isEmpty) return;

    final updated = Map<String, String>.from(state);
    var changed = false;
    for (final entry in latest.entries) {
      // A live event that landed while the seed was in flight is fresher than
      // this snapshot, so the seed only fills gaps.
      if (updated.containsKey(entry.key)) continue;
      updated[entry.key] = entry.value.status;
      changed = true;
    }
    if (changed) state = updated;
  }

  /// Subscribe to kind:20001 presence events over WebSocket.
  Future<void> _subscribePresenceUpdates() async {
    _presenceUnsub?.call();
    _presenceUnsub = null;
    _subscriptionVersion++;
    final version = _subscriptionVersion;

    final session = ref.read(relaySessionProvider.notifier);
    try {
      final unsub = await session.subscribe(
        const NostrFilter(kinds: [EventKind.presenceUpdate], limit: 0),
        _handlePresenceEvent,
      );
      // Guard: if build() re-fired while we were awaiting, discard this
      // subscription to avoid leaking it.
      if (version != _subscriptionVersion) {
        unsub();
        return;
      }
      _presenceUnsub = unsub;
    } catch (error) {
      debugPrint(
        '[PresenceCacheNotifier] presence subscription failed: $error',
      );
    }
  }

  void _handlePresenceEvent(NostrEvent event) {
    final pubkey = _subjectPubkey(event);
    if (!_tracked.contains(pubkey)) return;
    final status = event.content;
    if (!_presenceStatuses.contains(status)) return;
    if (state[pubkey] == status) return;
    final updated = Map<String, String>.from(state);
    updated[pubkey] = status;
    state = updated;
  }

  /// The user a presence event describes: the `p` tag when the relay
  /// synthesized it, otherwise the signing author.
  String _subjectPubkey(NostrEvent event) {
    for (final tag in event.tags) {
      if (tag.length >= 2 && tag[0] == 'p') return tag[1].toLowerCase();
    }
    return event.pubkey.toLowerCase();
  }
}

final presenceCacheProvider =
    NotifierProvider<PresenceCacheNotifier, Map<String, String>>(
      PresenceCacheNotifier.new,
    );
