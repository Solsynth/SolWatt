class MailAddressSuggestion {
  const MailAddressSuggestion({
    required this.address,
    required this.avatarUrl,
    required this.avatarSource,
    required this.gravatarUrl,
    this.name,
    this.lastSeen,
    this.interactionCount = 0,
    this.bimiUrl,
    this.workspaceId,
    this.alias = false,
  });

  final String address;
  final String? name;
  final DateTime? lastSeen;
  final int interactionCount;
  final String avatarUrl;
  final String avatarSource;
  final String gravatarUrl;
  final String? bimiUrl;
  final String? workspaceId;
  final bool alias;

  factory MailAddressSuggestion.fromJson(Map<String, dynamic> json) =>
      MailAddressSuggestion(
        address: json['address']?.toString() ?? '',
        name: _optionalString(json['name']),
        lastSeen: DateTime.tryParse(json['last_seen']?.toString() ?? ''),
        interactionCount: (json['interaction_count'] as num?)?.toInt() ?? 0,
        avatarUrl: json['avatar_url']?.toString() ?? '',
        avatarSource: json['avatar_source']?.toString() ?? '',
        gravatarUrl: json['gravatar_url']?.toString() ?? '',
        bimiUrl: _optionalString(json['bimi_url']),
        workspaceId: _optionalString(json['workspace_id']),
        alias: json['alias'] == true,
      );

  static String? _optionalString(Object? value) {
    final result = value?.toString().trim();
    return result == null || result.isEmpty ? null : result;
  }
}

/// The picture to show for [suggestion], or null when the caller's initials
/// read better.
///
/// The index reports where an avatar came from, and an address without a
/// Gravatar account still gets a URL there — Gravatar's own stand-in. A
/// stand-in says nothing about the contact, so those fall through to initials;
/// every picture the contact or their server actually chose is used as is.
String? emailAvatarUrl(MailAddressSuggestion? suggestion) {
  if (suggestion == null || suggestion.avatarUrl.isEmpty) return null;
  return _isGravatarStandIn(suggestion) ? null : suggestion.avatarUrl;
}

/// Whether the index's avatar is Gravatar's stand-in rather than a picture the
/// contact chose.
bool _isGravatarStandIn(MailAddressSuggestion suggestion) =>
    suggestion.avatarSource.trim().toLowerCase() == 'gravatar';
