#!/usr/bin/env bash
set -Eeuo pipefail
export SIMULATOR_UDID="$DUOCTL_UDID" CAPTURE_DEVICE=duo SCREENSHOTS_DIR=screenshots
case "$1" in
  duo-folded*) key=quran_single_page_scale; mode=single ;;
  duo-unfolded-portrait) key=quran_single_page_scale; mode=single ;;
  duo-half-open-book) key=quran_landscape_page_scale; mode=dualScreenBook ;;
  duo-half-open-tabletop) key=quran_single_page_scale; mode=single ;;
  *) key=quran_landscape_page_scale; mode=spread ;;
esac
bash .github/scripts/capture_reader_zoom.sh "$1" "$2" "$3" "$key" "$mode"
