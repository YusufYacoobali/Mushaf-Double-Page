"""Exercise both sides of the cover using real touches on page six."""
import json
import math
from pathlib import Path
import sys
import subprocess
import time

from duo_native_input import NativeInput, read, wait_for


def verify_folded_controls(source):
    device = NativeInput(source)
    layout = lambda: read(source)
    initial = device.snapshot()
    page = initial['page']
    assert initial['reader'] and initial['selected'] is None and page == 6, initial
    assert initial['zoom'] == 1 and device.display['activeScreen'] == 'cover'
    def expect(name, predicate, seconds=10):
        last = {}
        def check():
            nonlocal last
            last = device.snapshot()
            return last if predicate(last) else None
        try:
            snap = wait_for(check, name, seconds)
        except RuntimeError:
            device.record({'failed': name, 'snapshot': last})
            raise
        device.record({'verified': name, **{k: snap[k] for k in (
            'reader', 'routeWidgets', 'page', 'zoom', 'selected', 'bookmarks', 'audio', 'stripScrolls')}})
        return snap

    def tap(label, point=None):
        time.sleep(.35)
        if point is None:
            previous = None
            def settled_target():
                nonlocal previous
                points = device.snapshot()['items'].get(label, [])
                assert len(points) <= 1, (label, points)
                current = points[0] if points else None
                settled = current and previous and math.dist(current, previous) <= .5
                previous = current
                return current if settled else None
            point = wait_for(settled_target, f'visible and settled {label} button', 30)
        device.gesture(label, point)

    def zoom(selected):
        for label, target in [('Zoom out', .95), ('Zoom in', 1.)]:
            tap(label)
            expect(f'{label} while selected={selected}', lambda s:
                   abs(s['zoom'] - target) < .0001 and s['selected'] == selected and s['page'] == page)
            wait_for(lambda: abs(layout()['zoom'] - target) < .0001, 'rendered page zoom')

    def screenshot(name):
        subprocess.run(['duoctl', 'screenshot', str(device.out / (name + '.png'))], check=True, timeout=30)

    def dismiss():
        snapshot = device.snapshot()
        for label in ('@close', '@back', 'Back'):
            if label in snapshot['items']:
                tap(label)
                break
        else:
            tap('Dismiss modal barrier', [12, device.size[1] * .18])
        expect('Reader visible after dismiss', lambda s: s['reader'])

    try:
        # A page touch and a strip touch are traced separately before the tour.
        p = layout()['pages'][str(page)]
        surah, ayah, nx, ny = min(initial['ayahTargets'], key=lambda row: abs(row[3] - .48))
        point = [p['left'] + nx*p['width'], p['top'] + ny*p['height']]
        selected = f'{surah}:{ayah}'
        tap('Select printed ayah', point)
        expect('Printed ayah selected', lambda s: s['selected'] == selected)
        zoom(selected)
        screenshot('folded-selected')
        tap('Save ayah')
        expect('Ayah saved', lambda s: selected in s['bookmarks'])
        expect('Contextual strip overflows', lambda s: any(t['max'] > 1 for t in s['stripScrolls']))
        nav = layout()['navigation']
        x = nav['left'] + nav['width']/2
        start = nav['top'] + nav['height']*.87
        end = nav['top'] + nav['height']*.30
        device.gesture('Scroll contextual strip', [x, start], [x, end])
        expect('Strip scrolled, page retained', lambda s: s['page'] == page and
               any(t['offset'] > 1 for t in s['stripScrolls']))
        screenshot('folded-scrolled-controls')
        tap('Translate ayah')
        expect('Selected translation visible', lambda s: not s['reader'] and
               'Saheeh International' in s['items'] and any(selected in k for k in s['items']))
        screenshot('folded-translation')
        dismiss()
        tap('Remove ayah bookmark')
        expect('Ayah bookmark removed', lambda s: selected not in s['bookmarks'])
        device.gesture('Return strip to top', [x, end], [x, start])
        expect('Strip returned to top', lambda s: all(abs(t['offset']) < .5 for t in s['stripScrolls']))
        tap('Play ayah')
        expect('Selected ayah audible', lambda s: s['audio']['audible'] and s['audio']['ayah'] == ayah, 30)
        tap('Stop audio')
        expect('Selected playback stopped', lambda s: not s['audio']['active'])
        tap('Clear printed ayah', point)
        expect('Selection cleared', lambda s: s['selected'] is None)
        zoom(None)
        for label, widget in [('Translations, tafseer & notes', 'TranslationModal'),
                              ('Quran', 'SurahJuzNavigator'), ('Settings', 'Settings')]:
            tap(label)
            expect(f'{label} opened', lambda s: not s['reader'] and widget in s['routeWidgets'])
            dismiss()
        tap('Bookmarks')
        expect('Bookmarks sheet', lambda s: not s['reader'] and 'Add' in s['items'])
        tap('Add')
        expect('Page bookmark saved', lambda s: 'p' + str(page) in s['bookmarks'])
        tap('Dismiss bookmarks', [12, device.size[1] * .18])
        expect('Bookmarks dismissed with saved page', lambda s: s['reader'] and 'p' + str(page) in s['bookmarks'])
        # Exercise the independent native input path with the recording stopped.
        # Starting an XCTest session mid-verse can take longer than a short ayah.
        device.use_xctest = True
        tap('Audio')
        expect('Audio sheet', lambda s: 'AudioModal' in s['routeWidgets'])
        # The real editor scrolls on compact displays. Reveal Play by dragging
        # the sheet, never by invoking a callback from the observer.
        for _ in range(3):
            if 'Play' in device.snapshot()['items']:
                break
            device.gesture('Scroll audio sheet', [195, 515], [195, 249])
            time.sleep(.5)
        tap('Play')
        expect('Real audio advancing', lambda s: s['audio']['audible'] and s['audio']['positionMs'] > 0, 45)
        dismiss()
        tap('Pause')
        paused = expect('Playback paused', lambda s: s['audio']['paused'])
        original = paused['audio']['ayah']
        def paused_verse(s, ayah):
            reference = f"{paused['audio']['surah']}:{ayah}"
            # A manually queued verse has no audible cursor until Resume.
            # Require the new verse label and paused status in the visible dock.
            return s['audio']['paused'] and any(
                reference in label.split('\n')[0] and 'Paused' in label for label in s['items'])
        tap('Next ayah')
        expect('Next ayah displayed while paused', lambda s: paused_verse(s, original + 1))
        tap('Previous ayah')
        expect('Previous ayah displayed while paused', lambda s: paused_verse(s, original))
        tap('Audio settings')
        expect('Playback settings opened from strip', lambda s: 'AudioModal' in s['routeWidgets'] and
               s['audio']['paused'])
        dismiss()
        tap('Resume')
        expect('Previous ayah audible after resume', lambda s: s['audio']['audible'] and
               s['audio']['ayah'] == original and s['audio']['positionMs'] > 0)
        tap('Pause')
        held = expect('Playback held on previous ayah', lambda s: s['audio']['paused'] and
                      s['audio']['ayah'] == original)
        other = min((r for r in initial['ayahTargets'] if r[1] != original), key=lambda r: abs(r[3] - .65))
        verse = f'{other[0]}:{other[1]}'
        xy = [p['left'] + other[2]*p['width'], p['top'] + other[3]*p['height']]
        tap('Select another printed ayah', xy)
        expect('Separate selection during playback', lambda s: s['selected'] == verse and
               'Play selected ayah' in s['items'])
        tap('Play selected ayah')
        expect('Playback switched to selected ayah', lambda s: s['audio']['audible'] and
               s['audio']['ayah'] == other[1] and s['audio']['session'] != held['audio']['session'])
        tap('Pause')
        paused_audio = expect('Selected playback paused', lambda s: s['audio']['paused'])['audio']
        def retained(s):
            return (s['page'] == page and s['selected'] == verse and s['zoom'] == 1 and
                    s['audio']['paused'] and s['audio']['session'] == paused_audio['session'] and
                    s['audio']['positionMs'] == paused_audio['positionMs'] and
                    s['audio']['ayah'] == other[1])
        subprocess.run(['duoctl', '-d', device.udid, 'open'], check=True, timeout=60)
        subprocess.run(['duoctl', '-d', device.udid, 'rotate', 'portrait'], check=True, timeout=60)
        wait_for(lambda: not layout()['native']['closed'] and layout()['mode'] == 'single' and
                 layout()['navigationExpanded'], 'unfolded portrait controls', 20)
        expect('Unfold kept selection and paused audio', lambda s: retained(s) and 'Resume' in s['items'])
        screenshot('unfolded-paused-selection')
        subprocess.run(['duoctl', '-d', device.udid, 'close'], check=True, timeout=60)
        # The inner and cover panels have different physical axes. The same
        # device orientation that made the inner portrait returned a 678×466
        # landscape cover on the hosted Duo. Restore the observed cover pose.
        returned = subprocess.check_output(['duoctl', '-d', device.udid, 'rotate', device.display['orientation']],
                                           text=True, timeout=75)
        cover = json.loads(returned)
        device.record({'refoldedDisplay': cover})
        assert cover['activeScreen'] == 'cover' and cover['sizePoints'] == device.size, cover
        wait_for(lambda: layout()['native']['closed'] and layout()['viewport']['width'] == device.size[0],
                 'return to the cover', 20)
        expect('Cover restored same session', retained)
        tap('Stop audio')
        expect('Playback stopped', lambda s: not s['audio']['active'])
        tap('Clear selection after playback', xy)
        expect('Clean reader after controls', lambda s: s['reader'] and s['selected'] is None and s['zoom'] == 1)
    finally:
        device.close()


if __name__ == '__main__':
    verify_folded_controls(Path(sys.argv[1]))
