import 'dart:io';
import 'package:flutter/material.dart';

class QuranPageView {
  static Widget single({
    required int logicalPage,
    required bool optimizedPortrait,
    required String Function(int) imagePath,
  }) {
    return InteractiveViewer(
      panEnabled: false,
      minScale: 1,
      maxScale: 3,
      child: FractionallySizedBox(
        heightFactor: optimizedPortrait ? 0.9 : 1.0,
        child: Image.file(
          File(imagePath(logicalPage)),
          fit: optimizedPortrait ? BoxFit.fill : BoxFit.contain,
        ),
      ),
    );
  }

  static Widget double({
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
