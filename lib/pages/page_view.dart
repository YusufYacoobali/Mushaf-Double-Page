import 'dart:io';
import 'package:flutter/material.dart';
import '../utils/cache.dart'; // your QuranPageCache

class QuranPageView {
  static const double minPageScalePortrait = 0.7;
  static const double maxPageScalePortrait = 0.85;
  static const double minPageScaleLandscape = 0.60;
  static const double maxPageScaleLandscape = 0.9;

  static const ColorFilter invertFilter = ColorFilter.matrix([
    -1, 0, 0, 0, 255,
    0, -1, 0, 0, 255,
    0, 0, -1, 0, 255,
    0, 0, 0, 1, 0,
  ]);

  // ---------------------
  // SINGLE PAGE
  // ---------------------
  static Widget singlePage({
    required int logicalPage,
    required double pageScale,
    required String Function(int) imagePath,
    required bool isDarkMode,
  }) {
    final clamped = pageScale.clamp(minPageScalePortrait, maxPageScalePortrait);
    final path = imagePath(logicalPage);
    Widget image = FittedBox(        // ← restore the old fill behaviour
      fit: BoxFit.fill,
      child: QuranPageCache.getPage(path),
    );

    // ✅ only apply filter if dark mode
    if (isDarkMode) {
      image = ColorFiltered(
        colorFilter: invertFilter,
        child: image,
      );
    }

    return InteractiveViewer(
      panEnabled: false,
      minScale: 1,
      maxScale: 3,
      child: FractionallySizedBox(
        heightFactor: clamped,
        child: image,
      ),
    );
  }

  static Widget doublePage({
    required int spreadIndex,
    required String Function(int) imagePath,
    required int totalPages,
    required double pageScale,
    required bool isDarkMode,
  }) {
    final leftIndex = spreadIndex * 2;
    final rightIndex = leftIndex + 1;

    Widget buildPage(int index) {

      final path = imagePath(index);
      Widget image = QuranPageCache.getPage(path);

      if (isDarkMode) {
        image = ColorFiltered(
          colorFilter: invertFilter,
          child: image,
        );
      }
      return image;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final pageWidth =
        (constraints.maxWidth / 2 * pageScale).clamp(0.0, constraints.maxWidth / 2);

        Widget? leftPage;
        Widget? rightPage;

        if (leftIndex < totalPages) {
          leftPage = SizedBox(width: pageWidth, child: buildPage(leftIndex));
        }
        if (rightIndex < totalPages) {
          rightPage = SizedBox(width: pageWidth, child: buildPage(rightIndex));
        }

        return SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (leftPage != null) leftPage,
              if (leftPage != null && rightPage != null) const SizedBox(width: 1),
              if (rightPage != null) rightPage,
            ],
          ),
        );
      },
    );
  }
}