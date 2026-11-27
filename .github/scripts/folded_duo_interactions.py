"""Exercise both sides of the cover using real touches on page six."""
from pathlib import Path
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
            observed = device.snapshot()
            points = observed['items'].get(label, [])
            assert len(points) == 1, (label, observed['items'])
            point = points[0]
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
        if not device.snapshot()['reader']:
            dismiss()
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
        tap('Next ayah')
        expect('Next ayah rendered', lambda s: s['audio']['ayah'] == original + 1)
        tap('Previous ayah')
        expect('Previous ayah rendered', lambda s: s['audio']['ayah'] == original)
        tap('Resume')
        expect('Playback resumed', lambda s: s['audio']['audible'])
        tap('Stop audio')
        expect('Playback stopped', lambda s: not s['audio']['active'])
        expect('Clean reader after controls', lambda s: s['reader'] and s['selected'] is None and s['zoom'] == 1)
    finally:
        device.close()
