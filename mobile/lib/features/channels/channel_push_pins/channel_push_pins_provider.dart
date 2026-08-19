import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nostr/nostr.dart' as nostr;

import '../../../shared/community/community_provider.dart';
import '../../../shared/push/push_bridge.dart';
import '../../../shared/relay/relay.dart';
import 'channel_push_pins_storage.dart';

class ChannelPushPinsState {
  final bool isReady;
  final ChannelPushPinStore store;

  /// Bumped on every change. The push lease bootstrap watches this to decide
  /// whether the lease it published still describes what the user asked for.
  final int version;

  const ChannelPushPinsState({
    this.isReady = false,
    this.store = const ChannelPushPinStore(),
    this.version = 0,
  });

  bool isPinned(String channelId) => store.isPinned(channelId);

  List<String> get pinnedChannelIds => store.pinnedChannelIds;
}

class ChannelPushPinsNotifier extends Notifier<ChannelPushPinsState> {
  ChannelPushPinsStorage? _storage;

  @override
  ChannelPushPinsState build() {
    _storage = null;
    final relayConfig = ref.watch(relayConfigProvider);
    final nsec = relayConfig.nsec?.trim();
    if (nsec == null || nsec.isEmpty) return const ChannelPushPinsState();

    final pubkey = _safePubkeyFromNsec(nsec);
    if (pubkey == null || pubkey.isEmpty) return const ChannelPushPinsState();

    final storage = ChannelPushPinsStorage(pubkey);
    _storage = storage;

    Future.microtask(() async {
      final store = await storage.load();
      if (_storage != storage) return;
      state = ChannelPushPinsState(isReady: true, store: store, version: 1);
    });

    return const ChannelPushPinsState();
  }

  Future<void> setPinned(String channelId, bool pinned) async {
    final storage = _storage;
    if (storage == null) return;
    final entry = ChannelPushPinEntry(
      pinned: pinned,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    final store = state.store.withChannel(channelId, entry);
    // Emit before persisting: the toggle is the user's intent, and a failed
    // write must not leave the switch showing the opposite of what they chose.
    state = ChannelPushPinsState(
      isReady: true,
      store: store,
      version: state.version + 1,
    );
    await storage.save(store);
    // Re-export before the lease is republished. The extension reads the
    // snapshot at wake time, so a pin that reaches the relay first would wake
    // the device for a channel the extension still cannot describe.
    final communities = await ref.read(communityListProvider.future);
    await registerBuzzPushCommunitySnapshot(communities);
  }

  Future<void> toggle(String channelId) =>
      setPinned(channelId, !state.isPinned(channelId));
}

final channelPushPinsProvider =
    NotifierProvider<ChannelPushPinsNotifier, ChannelPushPinsState>(
      ChannelPushPinsNotifier.new,
    );

String? _safePubkeyFromNsec(String nsec) {
  try {
    final privkeyHex = nostr.Nip19.decode(payload: nsec).data;
    if (privkeyHex.isEmpty) return null;
    return nostr.Keys(privkeyHex).public;
  } catch (_) {
    return null;
  }
}
