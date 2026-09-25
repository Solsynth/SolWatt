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
