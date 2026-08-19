import '../relay/nostr_models.dart';

const buzzPushFallbackBody = 'Reconnect to your relay now';

class BuzzPushCommunitySnapshot {
  final String id;
  final String name;
  final String relayUrl;
  final String? pubkey;

  /// Channels pinned for whole-channel push. The lease decides what wakes the
  /// device; this decides what the notification service extension is able to
  /// describe. A wake whose cause the extension cannot fetch renders as an
  /// unrelated older mention, so both lists are written from the same source.
  final List<String> pinnedChannels;

  const BuzzPushCommunitySnapshot({
    required this.id,
    required this.name,
    required this.relayUrl,
    this.pubkey,
    this.pinnedChannels = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'relayUrl': relayUrl,
    if (pubkey != null) 'pubkey': pubkey,
    if (pinnedChannels.isNotEmpty) 'pinnedChannels': pinnedChannels,
  };

  factory BuzzPushCommunitySnapshot.fromJson(Map<String, dynamic> json) {
    final rawPinned = json['pinnedChannels'];
    return BuzzPushCommunitySnapshot(
      id: json['id'] as String,
      name: json['name'] as String,
      relayUrl: json['relayUrl'] as String,
      pubkey: json['pubkey'] as String?,
      pinnedChannels: rawPinned is List
          ? [
              for (final value in rawPinned)
                if (value is String) value,
            ]
          : const [],
    );
  }
}

class BuzzPushResolution {
  final String title;
  final String body;
  final String? subtitle;
  final String? threadIdentifier;

  const BuzzPushResolution({
    required this.title,
    required this.body,
    this.subtitle,
    this.threadIdentifier,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'body': body,
    if (subtitle != null) 'subtitle': subtitle,
    if (threadIdentifier != null) 'threadIdentifier': threadIdentifier,
  };
}

BuzzPushResolution? resolveBuzzPushNotification({
  required List<NostrEvent> events,
  required String myPubkey,
  required String communityName,
  String? channelName,
  Map<String, ProfileData> profilesByPubkey = const {},
}) {
  final normalizedPubkey = myPubkey.toLowerCase();
  final candidates = [
    for (final event in events)
      if (_isUserVisiblePushEvent(event, normalizedPubkey)) event,
  ];
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) {
    final created = b.createdAt.compareTo(a.createdAt);
    return created != 0 ? created : a.id.compareTo(b.id);
  });
  final event = candidates.first;
  final author = profilesByPubkey[event.pubkey.toLowerCase()];
  final title = _firstNonEmpty([
    author?.displayName,
    author?.nip05,
    _shortPubkey(event.pubkey),
  ]);
  final body = _previewBody(event.content);
  if (body.isEmpty) return null;
  return BuzzPushResolution(
    title: title,
    subtitle: channelName ?? communityName,
    body: body,
    threadIdentifier: event.channelId ?? communityName,
  );
}

bool _isUserVisiblePushEvent(NostrEvent event, String normalizedPubkey) {
  if (!EventKind.channelMessageEventKinds.contains(event.kind)) return false;
  if (event.pubkey.toLowerCase() == normalizedPubkey) return false;
  return true;
}

String _previewBody(String content) {
  String stripMarkdownLinks(String input) {
    return input.replaceAllMapped(
      RegExp(r'!?\[([^\]]*)\]\([^)]*\)'),
      (match) => match.group(1) ?? '',
    );
  }

  final stripped =
      stripMarkdownLinks(
            stripMarkdownLinks(
              content
                  .replaceAll(RegExp(r'```[\s\S]*?```'), '[code]')
                  .replaceAllMapped(
                    RegExp(r'`([^`]*)`'),
                    (match) => match.group(1) ?? '',
                  ),
            ),
          )
          .replaceAll(RegExp(r'https?://\S+'), '[link]')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
  if (stripped.length <= 180) return stripped;
  return '${stripped.substring(0, 177).trimRight()}…';
}

String _shortPubkey(String pubkey) {
  if (pubkey.length <= 8) return pubkey;
  return '${pubkey.substring(0, 8)}…';
}

String _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  }
  return 'Buzz';
}
