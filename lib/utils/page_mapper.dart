/// Utility class responsible for mapping page numbers
/// between portrait (single page) and landscape (two-page) modes
class PageMapper {
  static const int indopakLastFilePage = 851;
  static const int madaniLastFilePage = 624;

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
    if (portrait) return logical;

    // left page of a landscape spread must be even (0-based pair start)
    final left = logical.isOdd ? logical - 1 : logical;
    return left ~/ 2;
  }

  static int logicalFromPageIndex(int index, bool portrait) {
    return portrait ? index : index * 2;
  }
}
