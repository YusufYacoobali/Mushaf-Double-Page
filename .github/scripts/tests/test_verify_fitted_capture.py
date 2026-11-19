import copy
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

from PIL import Image, ImageDraw


spec = importlib.util.spec_from_file_location(
    'fitted_capture', Path(__file__).parents[1] / 'verify_fitted_capture.py')
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)
ASPECT = 721 / 1058


def rect(left, top, width, height):
    return dict(left=left, top=top, width=width, height=height)


def snapshot(posture='portrait', zoom=1):
    if posture == 'folded':
        viewport, safe, mode = (466, 678), [rect(0, 0, 382, 630)], 'single'
    elif posture == 'portrait':
        viewport, safe, mode = (669, 951), [rect(0, 0, 669, 930)], 'single'
    elif posture == 'landscape':
        viewport, safe, mode = (951, 669), [rect(8, 24, 931, 624)], 'spread'
    else:
        viewport = (951, 669)
        safe, mode = [rect(8, 24, 392, 624), rect(424, 24, 515, 624)], 'dualScreenBook'
    data = dict(viewport=dict(width=viewport[0], height=viewport[1]),
                pixelRatio=1, mode=mode, fit=True, zoom=zoom,
                focusedPage=4, edition='indopak_tajweed', safeRegions=safe,
                timestamp='2026-11-19T11:00:01Z', navigation=None)
    if mode == 'single':
        reading = safe[0]
        width = min(reading['width'], reading['height'] * ASPECT) * zoom
        height = width / ASPECT
        pages = {'4': rect(reading['left'] + (reading['width'] - width) / 2,
                           reading['top'] + (reading['height'] - height) / 2, width, height)}
        regions = safe
    elif mode == 'spread':
        reading = safe[0]
        half = (reading['width'] - 1) / 2
        regions = [dict(reading, width=half), dict(reading, left=reading['left'] + half + 1, width=half)]
        width = min(half, reading['height'] * ASPECT) * zoom
        height = width / ASPECT
        left = reading['left'] + (reading['width'] - (2 * width + 1)) / 2
        top = reading['top'] + (reading['height'] - height) / 2
        pages = {'4': rect(left + width + 1, top, width, height),
                 '5': rect(left, top, width, height)}
    else:
        regions = safe
        reading = rect(8, 24, 931, 624)
        width = min(min(r['width'], r['height'] * ASPECT) for r in safe) * zoom
        height = width / ASPECT
        pages = {str(page): rect(r['left'] + (r['width'] - width) / 2,
                                 r['top'] + (r['height'] - height) / 2, width, height)
                 for page, r in [(5, safe[0]), (4, safe[1])]}
    return data | dict(readingBounds=reading, regions=regions, pages=pages)


class FittedCaptureTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.png = Path(self.directory.name) / 'actual.png'
        self.metadata = self.png.with_suffix('.layout.json')

    def save(self, data, blank=False):
        image = Image.new('RGB', tuple(data['viewport'].values()), 'black')
        draw = ImageDraw.Draw(image)
        if not blank:
            for region in data['pages'].values():
                left, top, right, bottom = map(round, capture.bounds(region))
                draw.rectangle((left, top, right - 1, bottom - 1), fill='white')
                draw.rectangle((left + 10, top + 10, right - 11, bottom - 11), fill=(20, 20, 20))
        if data['navigation']:
            left, top, right, bottom = capture.bounds(data['navigation'])
            draw.rectangle((left, top, right - 1, bottom - 1), fill=(50, 50, 50))
        image.save(self.png)
        self.metadata.write_text(json.dumps(data))

    def test_all_four_postures_accept_real_maximum_and_minimum_geometry(self):
        for posture, minimum in [('folded', .7), ('portrait', .7), ('landscape', .6), ('book', .6)]:
            for zoom in [minimum, 1]:
                with self.subTest(posture=posture, zoom=zoom):
                    data = snapshot(posture, zoom)
                    self.save(data)
                    result = capture.verify(self.png, self.metadata, zoom * 100, data['mode'])
                    self.assertTrue(result['verified'])

    def test_original_dock_trimmed_fit_cannot_pass_even_when_self_consistent(self):
        data = snapshot()
        shrunk = rect(0, 0, 669, 800)
        data['readingBounds'] = shrunk
        data['regions'] = [shrunk]
        data['pages'] = {'4': rect((669 - 800 * ASPECT) / 2, 0, 800 * ASPECT, 800)}
        self.save(data)
        with self.assertRaisesRegex(AssertionError, 'full safe display'):
            capture.verify(self.png, self.metadata, 100)

    def test_flat_physical_panels_cannot_accept_a_page_crossing_the_hinge(self):
        data = snapshot('book')
        data['mode'] = 'spread'
        # Width, height and combined display containment remain plausible, but
        # the right page crosses the physical hinge at x=400..424.
        data['pages']['4']['left'] = 410
        self.save(data)
        with self.assertRaises(AssertionError):
            capture.verify(self.png, self.metadata, 100, 'spread')

    def test_floating_navigation_may_cover_bottom_paper_edge(self):
        data = snapshot()
        data['navigation'] = rect(0, 850, 669, 90)
        self.save(data)
        self.assertTrue(capture.verify(self.png, self.metadata, 100)['verified'])

    def test_navigation_mask_does_not_hide_an_unrelated_missing_paper_edge(self):
        data = snapshot()
        data['navigation'] = rect(0, 850, 669, 90)
        self.save(data)
        image = Image.open(self.png)
        ImageDraw.Draw(image).rectangle((0, 0, 668, 4), fill='black')
        image.save(self.png)
        with self.assertRaisesRegex(AssertionError, 'missing paper edge'):
            capture.verify(self.png, self.metadata, 100)

    def test_blank_page_with_visible_navigation_cannot_pass(self):
        data = snapshot()
        data['navigation'] = rect(0, 850, 669, 90)
        self.save(data, blank=True)
        with self.assertRaisesRegex(AssertionError, 'blank or unrendered'):
            capture.verify(self.png, self.metadata, 100)

    def test_cached_seventy_percent_cannot_pass_as_requested_hundred(self):
        data = snapshot(zoom=.7)
        self.save(data)
        with self.assertRaisesRegex(AssertionError, 'wrong actual rendered zoom'):
            capture.verify(self.png, self.metadata, 100)

    def test_stale_timestamp_and_wrong_posture_cannot_pass(self):
        data = snapshot()
        after = datetime(2026, 11, 19, 11, 0, 2, tzinfo=timezone.utc).timestamp()
        with self.assertRaisesRegex(AssertionError, 'stale rendered geometry'):
            capture.assert_capture_state(data, 100, 'single', after)
        with self.assertRaisesRegex(AssertionError, 'wrong reading mode'):
            capture.assert_capture_state(data, 100, 'dualScreenBook')

    def test_viewport_from_a_different_display_cannot_pass(self):
        data = snapshot()
        self.save(data)
        Image.new('RGB', (466, 678), 'white').save(self.png)
        with self.assertRaisesRegex(AssertionError, 'stale viewport geometry'):
            capture.verify(self.png, self.metadata, 100)

    def test_safe_panel_geometry_is_required_and_must_be_inside_display(self):
        data = snapshot()
        missing = copy.deepcopy(data)
        missing.pop('safeRegions')
        with self.assertRaisesRegex(AssertionError, 'independent safe display'):
            capture.assert_capture_state(missing, 100, 'single')
        data['safeRegions'] = [rect(-30, 0, 669, 930)]
        with self.assertRaisesRegex(AssertionError, 'outside viewport'):
            capture.fitted_regions(data, ASPECT)


if __name__ == '__main__':
    unittest.main()
