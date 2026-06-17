import 'package:flutter/material.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, this.imageUrl, this.name, this.radius = 20});

  final String? imageUrl;
  final String? name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final trimmedUrl = imageUrl?.trim() ?? '';

    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: ClipOval(
        child: trimmedUrl.isEmpty
            ? _fallback(context)
            : Image.network(
                trimmedUrl,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _fallback(context);
                },
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return _fallback(context);
                },
              ),
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    final initial = _initial;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      color: colorScheme.primaryContainer,
      child: initial == null
          ? Icon(
              Icons.person,
              size: radius,
              color: colorScheme.onPrimaryContainer,
            )
          : Text(
              initial,
              style: TextStyle(
                color: colorScheme.onPrimaryContainer,
                fontSize: radius * 0.8,
                fontWeight: FontWeight.bold,
              ),
            ),
    );
  }

  String? get _initial {
    final trimmedName = name?.trim() ?? '';
    if (trimmedName.isEmpty) return null;
    return trimmedName.characters.first;
  }
}
