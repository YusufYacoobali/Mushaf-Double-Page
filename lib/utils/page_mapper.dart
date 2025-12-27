class PageMapper {
  static const int mushafPages = 851;

  static int displayFromPdf(int pdfPage, bool isPortrait) {
    return isPortrait
        ? pdfPage + 1
        : pdfPage * 2 + 1;
  }

  static int pdfFromDisplay(int displayPage, bool isPortrait) {
    return isPortrait
        ? displayPage - 1
        : (displayPage - 1) ~/ 2;
  }

  static int orientationMapper(int currentPage, bool isPortrait) {
    return isPortrait
        ? (currentPage * 2).toInt()
        : (currentPage ~/ 2);
  }
}
