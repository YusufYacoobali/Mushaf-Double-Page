
// Host requests take read-only snapshots of the current route. All input
// comes from the simulator digitizer or XCTest, outside of the Flutter app.
class _CoverProbe {
  _CoverProbe(this.reader, Directory dir)
    : request = File('${dir.path}/duo-request'),
      reply = File('${dir.path}/duo-snapshot.json'),
      trace = File('${dir.path}/duo-flutter.jsonl') {
    GestureBinding.instance.pointerRouter.addGlobalRoute(pointer);
    timer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!request.existsSync() || !reader.mounted) return;
      final id = request.readAsStringSync();
      request.deleteSync();
      final output = File('${reply.path}.tmp');
      output.writeAsStringSync(jsonEncode({'id': id, ...snapshot()}));
      output.renameSync(reply.path);
    });
  }

  final _MyPDFViewerState reader;
  final File request, reply, trace;
  late final Timer timer;
  void event(Map<String, Object?> row) => trace.writeAsStringSync(
    '${jsonEncode({'time': DateTime.now().millisecondsSinceEpoch / 1000, ...row})}\n',
    mode: FileMode.append,
  );
  void pointer(PointerEvent e) {
    if (e is PointerDownEvent || e is PointerUpEvent) {
      event({'pointer': e.runtimeType.toString(), 'x': e.position.dx, 'y': e.position.dy});
    }
  }

  Map<String, Object?> snapshot() {
    final items = <String, List<List<double>>>{};
    final types = <String>{};
    final scrolls = <Map<String, double>>[];
    final binding = WidgetsBinding.instance;
    final view = View.of(reader.context);
    void visit(Element element) {
      final w = element.widget;
      if (element is StatefulElement && element.state is ScrollableState &&
          element.findAncestorWidgetOfExactType<ReaderDock>() != null) {
        final position = (element.state as ScrollableState).position;
        if (position.hasContentDimensions) {
          scrolls.add({'max': position.maxScrollExtent, 'offset': position.pixels});
        }
      }
      if (w.key == const ValueKey('surah-juz-panel') && ModalRoute.isCurrentOf(element) == true) {
        types.add('SurahJuzNavigator');
      }
      final label = switch (w) {
        Text() => w.data,
        Tooltip() => w.message,
        BackButton() => '@back',
        IconButton() when w.icon is Icon && (w.icon as Icon).icon == Icons.arrow_back_ios_new => '@back',
        Icon() when w.icon == Icons.close || w.icon == Icons.close_rounded => '@close',
        _ => null,
      };
      // Only current-route targets whose actual render ancestor is hit at
      // this point can be used for taps. Offstage and clipped rows are excluded.
      if (label != null && ModalRoute.isCurrentOf(element) == true) {
        final box = element.findRenderObject();
        if (box is RenderBox && box.attached && box.hasSize && !box.size.isEmpty) {
          final point = box.localToGlobal(box.size.center(Offset.zero));
          if (point.isFinite) {
            final hit = HitTestResult();
            binding.hitTestInView(hit, point, view.viewId);
            if (hit.path.any((entry) => identical(entry.target, box))) {
              (items[label] ??= []).add([point.dx, point.dy]);
            }
          }
        }
      }
      if (w is AudioModal || w is TranslationModal || w is Settings) {
        if (ModalRoute.isCurrentOf(element) == true) types.add(w.runtimeType.toString());
      }
      element.visitChildElements(visit);
    }
    binding.rootElement?.visitChildElements(visit);
    final page = reader._logicalPage;
    final audio = QuranAudioController.instance;
    return {
      'reader': ModalRoute.isCurrentOf(reader.context) == true, 'routeWidgets': types.toList(),
      'items': items, 'stripScrolls': scrolls, 'page': page, 'zoom': reader._pageScalePortrait,
      'selected': reader._selPage == null ? null : '${reader._selSurah}:${reader._selAyah}',
      'bookmarks': reader._bookmarks.map((b) => b.isAyah ? '${b.surahNumber}:${b.ayah}' : 'p${b.pageNumber}').toList(),
      'audio': {'active': audio.hasActivePlayback, 'audible': audio.audible, 'paused': audio.paused,
        'session': audio.playbackSessionId, 'ayah': audio.currentAyah, 'surah': audio.currentSurah,
        'positionMs': audio.playbackPosition.inMilliseconds, 'status': audio.statusLabel},
      'ayahTargets': [
        for (final segment in PageAyahIndex.segmentsForPages([page], mushaf: reader._mushaf))
          for (final rect in AyahRectIndex.rectsFor(page, segment[0], segment[1], mushaf: reader._mushaf))
            [segment[0], segment[1], rect.center.dx, rect.center.dy],
      ],
    };
  }

  void dispose() {
    timer.cancel();
    GestureBinding.instance.pointerRouter.removeGlobalRoute(pointer);
  }
}
