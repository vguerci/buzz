import 'package:buzz/features/channels/channel_push_pins/channel_push_pins_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('round-trips pins for one identity', () async {
    const storage = ChannelPushPinsStorage('pubkey-a');
    await storage.save(
      const ChannelPushPinStore(
        channels: {
          'channel-a': ChannelPushPinEntry(pinned: true, updatedAt: 10),
          'channel-b': ChannelPushPinEntry(pinned: false, updatedAt: 11),
        },
      ),
    );

    final loaded = await storage.load();

    expect(loaded.isPinned('channel-a'), isTrue);
    expect(loaded.isPinned('channel-b'), isFalse);
    expect(loaded.pinnedChannelIds, ['channel-a']);
  });

  test('keys pins per identity', () async {
    await const ChannelPushPinsStorage('pubkey-a').save(
      const ChannelPushPinStore(
        channels: {'channel-a': ChannelPushPinEntry(pinned: true, updatedAt: 1)},
      ),
    );

    final other = await const ChannelPushPinsStorage('pubkey-b').load();

    expect(other.pinnedChannelIds, isEmpty);
  });

  test('returns an empty store rather than throwing on a corrupt blob', () async {
    SharedPreferences.setMockInitialValues({
      channelPushPinsKey('pubkey-a'): 'not json',
    });

    final loaded = await const ChannelPushPinsStorage('pubkey-a').load();

    expect(loaded.pinnedChannelIds, isEmpty);
  });

  test('pinned ids are sorted so an unchanged selection is stable', () {
    const store = ChannelPushPinStore(
      channels: {
        'channel-c': ChannelPushPinEntry(pinned: true, updatedAt: 1),
        'channel-a': ChannelPushPinEntry(pinned: true, updatedAt: 2),
      },
    );

    expect(store.pinnedChannelIds, ['channel-a', 'channel-c']);
  });

  test('merge keeps the most recently updated entry per channel', () {
    const local = ChannelPushPinStore(
      channels: {'channel-a': ChannelPushPinEntry(pinned: true, updatedAt: 5)},
    );
    const remote = ChannelPushPinStore(
      channels: {
        'channel-a': ChannelPushPinEntry(pinned: false, updatedAt: 9),
        'channel-b': ChannelPushPinEntry(pinned: true, updatedAt: 1),
      },
    );

    final merged = mergePushPinStores(local, remote);

    expect(merged.isPinned('channel-a'), isFalse);
    expect(merged.isPinned('channel-b'), isTrue);
  });
}
