class PageMapper {
  static const int totalPages = 851;
  static const int totalPagesHorizontal = 426;

  static int orientationMapper(int currentPage, bool isPortrait) {
    return isPortrait
        ? (currentPage * 2).toInt()
        : (currentPage ~/ 2);
  }

  static int bookmarkGoToMapper(int currentPage, bool isPortrait) {
    return isPortrait
        ? (totalPages - currentPage)
        : ((totalPages - currentPage) ~/ 2);
  }

  static int bookmarkAddMapper(int currentPage, bool isPortrait) {
    return isPortrait
        ? (totalPages - currentPage)
        : (totalPagesHorizontal - currentPage) * 2 - 1;
  }
}
