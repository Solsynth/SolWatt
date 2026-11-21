import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Circular avatar for the signed-in account.
///
/// The profile picture is used when available; otherwise the widget falls back
/// to the account's initials, and to a person glyph when there is no name yet.
/// Shared by the profile card, the rail's profile destination and the mobile
/// lens sheet so the account always looks the same wherever it appears.
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({
    super.key,
    this.displayName,
    this.avatarUrl,
    this.radius = 20,
  });

  final String? displayName;
  final String? avatarUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initials = _initials(displayName ?? '');
    final imageUrl = avatarUrl?.trim();
    final backgroundImage = imageUrl == null || imageUrl.isEmpty
        ? null
        : NetworkImage(imageUrl);

    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      foregroundImage: backgroundImage,
      child: initials.isEmpty
          ? Icon(
              Symbols.person,
              size: radius * 1.1,
              color: scheme.onPrimaryContainer,
            )
          : Text(
              initials,
              style: TextStyle(
                fontSize: radius * 0.72,
                fontWeight: FontWeight.w600,
                color: scheme.onPrimaryContainer,
              ),
            ),
    );
  }
}

String _initials(String name) {
  // The display name falls back to the bare handle (`@name`) when the account
  // has no nickname; the marker is not part of the person's initials.
  final normalized = name.trim().replaceFirst(RegExp(r'^@'), '');
  final parts = normalized
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0])
      .join()
      .toUpperCase();
  return parts;
}
