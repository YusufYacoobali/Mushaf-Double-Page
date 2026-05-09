import 'package:flutter/cupertino.dart';

/// Utility class responsible for mapping page numbers
/// between portrait (single page) and landscape (two-page) modes
class PageMapper {
  static const int indopakLastFilePage = 851;
  static const int madaniLastFilePage = 624;

  /// Total number of spreads in Portrait and landscape (two-page) mode
  // static const int totalPages = 851;
  // static const int totalPagesHorizontal = 426;

  /// Maps the current page index when orientation changes
  ///
  /// Portrait:
  ///   Each page becomes a two-page spread, so multiply by 2 if coming from landscape
  ///
  /// Landscape:
  ///   Each spread represents two pages, so divide by 2 if coming from portrait

  static int indoPakToMadani(int page) {
    return ((page / indopakLastFilePage) * madaniLastFilePage).round().clamp(
      1,
      madaniLastFilePage,
    );
  }

  static int madaniToIndoPak(int page) {
    return ((page / madaniLastFilePage) * indopakLastFilePage).round().clamp(
      1,
      indopakLastFilePage,
    );
  }

  /// Maps a bookmarked page when navigating to it
  ///
  /// Pages are stored inverted (from the end of the Mushaf),
  /// so we subtract from totalPages before applying orientation logic
  static int bookmarkGoToMapper(int currentPage, bool isPortrait) {
    return isPortrait ? (currentPage) : ((currentPage) ~/ 2);
  }

  static int pageIndexFromLogical(int logical, bool portrait) {
    if (portrait) {
      debugPrint('[MAP] logical $logical -> index $logical (portrait)');
      return logical;
    }

    // left page must be odd (1-based)
    final left = logical.isOdd ? logical - 1 : logical;
    final index = left ~/ 2;

    debugPrint(
      '[MAP] logical $logical -> left=$left -> spreadIndex=$index (landscape)',
    );

    return index;
  }

  static int logicalFromPageIndex(int index, bool portrait) {
    final logical = portrait ? index : index * 2;

    debugPrint('[MAP] index $index -> logical=$logical (portrait=$portrait)');

    return logical;
  }
}
