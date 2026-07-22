import 'package:flutter/material.dart';

import '../utils/app_palette.dart';

Widget barIcon({
  required IconData icon,
  required VoidCallback onPressed,
  required AppPalette palette,
}) {
  return IconButton(
    icon: Icon(icon, size: 22),
    color: palette.readerIcon,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    onPressed: onPressed,
  );
}
