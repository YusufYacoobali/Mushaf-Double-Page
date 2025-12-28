/// Utility class responsible for mapping page numbers
/// between portrait (single page) and landscape (two-page) modes
class PageMapper {
  /// Total number of spreads in Portrait and landscape (two-page) mode
  static const int totalPages = 851;
  static const int totalPagesHorizontal = 426;

  /// Maps the current page index when orientation changes
  ///
  /// Portrait:
  ///   Each page becomes a two-page spread, so multiply by 2 if coming from landscape
  ///
  /// Landscape:
  ///   Each spread represents two pages, so divide by 2 if coming from portrait
  static int orientationMapper(int currentPage, bool isPortrait) {
    return isPortrait
        ? (currentPage * 2).toInt()
        : (currentPage ~/ 2);
  }

  /// Maps a bookmarked page when navigating to it
  ///
  /// Pages are stored inverted (from the end of the Mushaf),
  /// so we subtract from totalPages before applying orientation logic
  static int bookmarkGoToMapper(int currentPage, bool isPortrait) {
    return isPortrait
        ? (totalPages - currentPage)
        : ((totalPages - currentPage) ~/ 2);
  }

  /// Maps the page number when adding a new bookmark
  static int bookmarkAddMapper(int currentPage, bool isPortrait) {
    return isPortrait
        ? (totalPages - currentPage)
        : (totalPagesHorizontal - currentPage) * 2 - 1;
  }
}
