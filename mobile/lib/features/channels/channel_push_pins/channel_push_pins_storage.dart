import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Channels the user asked to be pushed for on every message, not only when
/// mentioned. Stored per identity, in the shape `channel_mutes_storage.dart`
/// uses, so the relay-synced (kind:30078) lane can be added later without a
/// migration: same per-channel `updatedAt`, same last-writer-wins merge.
String channelPushPinsKey(String pubkey) => 'buzz.channel-push-pins.v1:$pubkey';

class ChannelPushPinEntry {
  final bool pinned;
  final int updatedAt;

  const ChannelPushPinEntry({required this.pinned, required this.updatedAt});

  Map<String, dynamic> toJson() => {'pinned': pinned, 'updatedAt': updatedAt};

  factory ChannelPushPinEntry.fromJson(Map<String, dynamic> json) =>
      ChannelPushPinEntry(
        pinned: json['pinned'] as bool,
        updatedAt: json['updatedAt'] as int,
      );
}

class ChannelPushPinStore {
  final int version;
  final Map<String, ChannelPushPinEntry> channels;

  const ChannelPushPinStore({this.version = 1, this.channels = const {}});

  bool isPinned(String channelId) => channels[channelId]?.pinned ?? false;

  /// The lease's `#h` values. Sorted so an unchanged selection produces an
  /// identical lease, and a republish is driven by intent rather than by map
  /// iteration order.
  List<String> get pinnedChannelIds {
    final ids = [
      for (final entry in channels.entries)
        if (entry.value.pinned) entry.key,
    ];
    ids.sort();
    return ids;
  }

  ChannelPushPinStore withChannel(String channelId, ChannelPushPinEntry entry) =>
      ChannelPushPinStore(
        version: version,
        channels: {...channels, channelId: entry},
      );

  Map<String, dynamic> toJson() => {
    'version': version,
    'channels': {for (final e in channels.entries) e.key: e.value.toJson()},
  };

  factory ChannelPushPinStore.fromJson(Map<String, dynamic> json) {
    final rawChannels = json['channels'];
    final channels = <String, ChannelPushPinEntry>{};
    if (rawChannels is Map) {
      for (final entry in rawChannels.entries) {
        if (entry.key is String && entry.value is Map<String, dynamic>) {
          final v = entry.value as Map<String, dynamic>;
          if (v['pinned'] is bool && v['updatedAt'] is int) {
            channels[entry.key as String] = ChannelPushPinEntry.fromJson(v);
          }
        }
      }
    }
    return ChannelPushPinStore(version: 1, channels: channels);
  }
}

ChannelPushPinStore mergePushPinStores(
  ChannelPushPinStore local,
  ChannelPushPinStore remote,
) {
  final merged = <String, ChannelPushPinEntry>{...local.channels};
  for (final entry in remote.channels.entries) {
    final existing = merged[entry.key];
    if (existing == null || entry.value.updatedAt > existing.updatedAt) {
      merged[entry.key] = entry.value;
    }
  }
  return ChannelPushPinStore(channels: merged);
}

class ChannelPushPinsStorage {
  final String pubkey;

  const ChannelPushPinsStorage(this.pubkey);

  Future<ChannelPushPinStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(channelPushPinsKey(pubkey));
    if (raw == null || raw.isEmpty) return const ChannelPushPinStore();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const ChannelPushPinStore();
      return ChannelPushPinStore.fromJson(decoded);
    } on FormatException {
      // A corrupt blob must not strand the user without notifications; the
      // next toggle rewrites it.
      return const ChannelPushPinStore();
    }
  }

  Future<void> save(ChannelPushPinStore store) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      channelPushPinsKey(pubkey),
      jsonEncode(store.toJson()),
    );
  }
}
