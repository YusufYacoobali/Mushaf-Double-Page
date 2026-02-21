import 'dart:core';
import 'dart:io';
import 'package:flutter/material.dart';

class QuranPageView {
  static const double minPageScalePortrait = 0.7;
  static const double maxPageScalePortrait = 0.8;

  static const double minPageScaleLandscape = 0.65;
  static const double maxPageScaleLandscape = 0.95;

  static Widget singlePage({
    required int logicalPage,
    required double pageScale,
    required String Function(int) imagePath,
  }) {
    final clamped = pageScale.clamp(minPageScalePortrait, maxPageScalePortrait);

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
    required String Function(int) imagePath,
    required int totalPages,
    required double pageScale, // e.g., 1.0 normal, >1 zoom in
  }) {
    final leftIndex = spreadIndex * 2;
    final rightIndex = leftIndex + 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Max width per page considering zoom
        final pageWidth = (constraints.maxWidth / 2 * pageScale).clamp(0.0, constraints.maxWidth / 2);
        return SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child:  Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Left page
              SizedBox(
                width: pageWidth,
                child: Image.file(
                  File(imagePath(leftIndex)),
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 1),
              // Right page (if exists)
              if (rightIndex < totalPages)
                SizedBox(
                  width: pageWidth,
                  child: Image.file(
                    File(imagePath(rightIndex)),
                    fit: BoxFit.contain,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }








// static Widget doublePage({
  //   required int spreadIndex,
  //   required bool optimizedLandscape,
  //   required String Function(int) imagePath,
  //   required int totalPages,
  // }) {
  //   final left = spreadIndex * 2;
  //   final right = left + 1;
  //
  //   if (!optimizedLandscape) {
  //     return InteractiveViewer(
  //       panEnabled: false,
  //       minScale: 1,
  //       maxScale: 3,
  //       child: Row(
  //         mainAxisAlignment: MainAxisAlignment.center,
  //         children: [
  //           Image.file(File(imagePath(left))),
  //           const SizedBox(width: 2),
  //           if (right < totalPages)
  //             Image.file(File(imagePath(right))),
  //         ],
  //       ),
  //     );
  //   }
  //
  //   return SingleChildScrollView(
  //     child: Row(
  //       children: [
  //         Expanded(
  //           child: Image.file(
  //             File(imagePath(left)),
  //             fit: BoxFit.fitWidth,
  //           ),
  //         ),
  //         const SizedBox(width: 4),
  //         if (right < totalPages)
  //           Expanded(
  //             child: Image.file(
  //               File(imagePath(right)),
  //               fit: BoxFit.fitWidth,
  //             ),
  //           ),
  //       ],
  //     ),
  //   );
  // }
}
