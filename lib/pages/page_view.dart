import 'dart:core';
import 'dart:io';
import 'package:flutter/material.dart';

class QuranPageView {
  static const double minPageScale = 0.7;
  static const double maxPageScale = 0.8;

  static Widget singlePage({
    required int logicalPage,
    required double pageScale, // from slider / buttons
    required String Function(int) imagePath,
  }) {
    final clamped = pageScale.clamp(minPageScale, maxPageScale);

    return InteractiveViewer(
      panEnabled: false,
      minScale: 1,
      maxScale: 3,
      child: FractionallySizedBox(
        heightFactor: clamped,
        child: Image.file(
          File(imagePath(logicalPage)),
          fit: BoxFit.fill,
        ),
      ),
    );
  }


  static Widget doublePage({
    required int spreadIndex,
    required bool optimizedLandscape,
    required String Function(int) imagePath,
    required int totalPages,
  }) {
    final left = spreadIndex * 2;
    final right = left + 1;

    if (!optimizedLandscape) {
      return InteractiveViewer(
        panEnabled: false,
        minScale: 1,
        maxScale: 3,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.file(File(imagePath(left))),
            const SizedBox(width: 2),
            if (right < totalPages)
              Image.file(File(imagePath(right))),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Row(
        children: [
          Expanded(
            child: Image.file(
              File(imagePath(left)),
              fit: BoxFit.fitWidth,
            ),
          ),
          const SizedBox(width: 4),
          if (right < totalPages)
            Expanded(
              child: Image.file(
                File(imagePath(right)),
                fit: BoxFit.fitWidth,
              ),
            ),
        ],
      ),
    );
  }
}
