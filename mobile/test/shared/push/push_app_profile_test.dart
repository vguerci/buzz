import 'package:buzz/shared/push/dev_push_lease.dart';
import 'package:buzz/shared/push/push_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

const _relayPubkey =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Map<String, dynamic> _descriptorJson(String profileId) => {
  'supported_extensions': ['nip-er', 'nip-pl'],
  'push': {
    'origin': 'wss://tenant.example:8443',
    'keys': [
      {'id': 'relay-v1', 'pubkey': _relayPubkey, 'current': true},
    ],
    'app_profiles': [
      {'id': profileId, 'transport': 'apns'},
    ],
    'push_kinds': [7, 9, 1059, 40007, 46010],
    'urgent_kinds': <int>[],
    'h_grammar': 'uuid-v4-lowercase',
    'class_support': {
      'apns': ['silent', 'default', 'time_sensitive'],
    },
    'limitation': {
      'max_lease_ttl': 2592000,
      'max_leases_per_pubkey': 16,
      'max_subscriptions_per_lease': 16,
      'max_kinds': 16,
      'max_authors': 20,
      'max_h': 50,
      'max_tag_values': 20,
      'max_ignore': 8,
      'max_content_len': 65536,
      'max_plaintext_len': 32768,
      'max_endpoint_len': 4096,
      'max_string_len': 512,
    },
  },
};

void main() {
  tearDown(() => buzzPushAppProfile = 'buzz-ios-sandbox');

  test('the descriptor check follows the profile this build enrols as', () {
    buzzPushAppProfile = 'buzz-ios-production';

    // A release build carries a production APNs token and attests production,
    // so a relay offering only the sandbox profile cannot serve it. Enrolling
    // anyway is what produced an opaque `400 invalid_request` from a gateway
    // whose BUZZ_PUSH_ENABLED_PROFILES listed production alone.
    expect(
      () => BuzzPushLeaseDescriptor.fromRelayInformation(
        _descriptorJson('buzz-ios-sandbox'),
      ),
      throwsA(isA<FormatException>()),
    );

    expect(
      BuzzPushLeaseDescriptor.fromRelayInformation(
        _descriptorJson('buzz-ios-production'),
      ).transport,
      'apns',
    );
  });

  test('a debug build still matches the sandbox profile', () {
    buzzPushAppProfile = 'buzz-ios-sandbox';

    expect(
      BuzzPushLeaseDescriptor.fromRelayInformation(
        _descriptorJson('buzz-ios-sandbox'),
      ).transport,
      'apns',
    );
  });
}
