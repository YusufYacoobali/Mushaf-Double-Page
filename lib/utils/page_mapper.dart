/// Utility class responsible for mapping page numbers
/// between single pages and RTL spreads, independently of orientation.
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

  /// Bookmarks store one-based file pages, independent of the current page mode.
  static int bookmarkGoToMapper(int currentPage, bool isPortrait) {
    return pageIndexFromLogical(currentPage, isPortrait);
  }

  static int pageIndexFromLogical(int logical, bool portrait) {
    if (portrait) return (logical - 1).clamp(0, indopakLastFilePage);

    // The even file page is on the right, followed by the odd page on the left.
    // Slot zero is blank at the beginning of the Mushaf.
    final right = logical.isOdd ? logical - 1 : logical;
    return right ~/ 2;
  }

  static int logicalFromPageIndex(int index, bool portrait) {
    return portrait ? index + 1 : (index * 2).clamp(1, indopakLastFilePage);
  }

  static List<int> visiblePages(int focused, bool single, int lastPage) {
    final first = single ? focused : (focused ~/ 2) * 2;
    return [
      for (var p = first; p < first + (single ? 1 : 2); p++)
        if (p >= 1 && p <= lastPage) p,
    ];
  }
}
