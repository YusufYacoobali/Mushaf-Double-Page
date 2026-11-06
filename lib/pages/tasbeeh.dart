import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../components/tasbeeh_counter.dart';
import '../utils/app_motion.dart';
import '../utils/app_palette.dart';
import '../utils/tasbeeh_store.dart';

class TasbeehPage extends StatefulWidget {
  const TasbeehPage({super.key, this.store});
  final TasbeehStore? store;
  @override
  State<TasbeehPage> createState() => _TasbeehPageState();
}

class _TasbeehPageState extends State<TasbeehPage> with WidgetsBindingObserver {
  late final TasbeehStore _store = widget.store ?? TasbeehStore.instance;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_store.restore());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_store.flush());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_store.flush());
    super.dispose();
  }

  void _count() {
    if (!_store.ready) return;
    final reached = _store.increment();
    if (_store.vibration) {
      unawaited(
        reached && _store.targetFeedback
            ? HapticFeedback.mediumImpact()
            : HapticFeedback.selectionClick(),
      );
    }
    if (_store.sound) unawaited(SystemSound.play(SystemSoundType.click));
    if (reached && _store.targetFeedback) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Target of ${_store.target} reached'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: AppMotion.style(context),
      builder: (ctx) => AlertDialog(
        title: const Text('Reset this count?'),
        content: Text(
          'Reset ${_store.selected.label} to 00000? Other counts are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed == true) _store.reset();
  }

  Future<String?> _textInput(String title, {bool number = false}) async {
    final input = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      animationStyle: AppMotion.style(context),
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: input,
          autofocus: true,
          maxLength: number ? 30 : 80,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          inputFormatters: number
              ? [FilteringTextInputFormatter.digitsOnly]
              : null,
          decoration: InputDecoration(
            labelText: number ? 'Positive target' : 'Dhikr name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (input.text.trim().isEmpty ||
                  (number &&
                      (BigInt.tryParse(input.text) ?? BigInt.zero) <=
                          BigInt.zero)) {
                return;
              }
              Navigator.pop(ctx, input.text.trim());
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // Route exit animations may still reference the controller.
    Future<void>.delayed(AppMotion.exit, input.dispose);
    return result;
  }

  Future<void> _selector() async {
    final palette = AppPalette.of(context);
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: AppMotion.style(context),
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: palette.surface,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * .75,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Choose your dhikr')),
            for (final dhikr in _store.dhikrs)
              ListTile(
                title: Text(dhikr.label),
                subtitle: dhikr.custom
                    ? null
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dhikr.arabic,
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(
                              fontFamily: 'NotoNaskh',
                              fontSize: 22,
                            ),
                          ),
                          Text(dhikr.meaning),
                        ],
                      ),
                trailing: _store.selected.id == dhikr.id
                    ? Icon(Icons.check, color: palette.accent)
                    : null,
                onTap: () {
                  _store.select(dhikr.id);
                  Navigator.pop(ctx);
                },
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Custom dhikr'),
              onTap: () async {
                Navigator.pop(ctx);
                final label = await _textInput('Custom dhikr');
                if (label != null) _store.addCustom(label);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _settings() async {
    final palette = AppPalette.of(context);
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: AppMotion.style(context),
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: palette.surface,
      builder: (ctx) => ListenableBuilder(
        listenable: _store,
        builder: (ctx, _) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * .8,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(title: Text('Tasbeeh settings')),
                SwitchListTile(
                  title: const Text('Vibration'),
                  value: _store.vibration,
                  onChanged: (v) => _store.preferences(vibration: v),
                ),
                SwitchListTile(
                  title: const Text('Sound'),
                  value: _store.sound,
                  onChanged: (v) => _store.preferences(sound: v),
                ),
                SwitchListTile(
                  title: const Text('Target completion feedback'),
                  value: _store.targetFeedback,
                  onChanged: (v) => _store.preferences(targetFeedback: v),
                ),
                ListTile(
                  title: const Text('Target'),
                  subtitle: Text('For ${_store.selected.label}'),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final target in [null, 33, 100])
                        ChoiceChip(
                          label: Text(target == null ? 'None' : '$target'),
                          selected:
                              _store.target ==
                              (target == null ? null : BigInt.from(target)),
                          onSelected: (_) => _store.setTarget(
                            target == null ? null : BigInt.from(target),
                          ),
                        ),
                      ActionChip(
                        label: Text(
                          _store.target != null &&
                                  _store.target != BigInt.from(33) &&
                                  _store.target != BigInt.from(100)
                              ? 'Custom: ${_store.target}'
                              : 'Custom',
                        ),
                        onPressed: () async {
                          final target = await _textInput(
                            'Custom target',
                            number: true,
                          );
                          if (target != null) {
                            _store.setTarget(BigInt.parse(target));
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const ListTile(title: Text('Custom dhikr')),
                for (final dhikr in _store.dhikrs.where((d) => d.custom))
                  ListTile(
                    title: Text(dhikr.label),
                    trailing: IconButton(
                      tooltip: 'Delete ${dhikr.label}',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final remove = await showDialog<bool>(
                          context: context,
                          builder: (dctx) => AlertDialog(
                            title: const Text('Delete custom dhikr?'),
                            content: Text(
                              'Delete ${dhikr.label} and its saved count?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dctx, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(dctx, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (remove == true) _store.removeCustom(dhikr.id);
                      },
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Add custom dhikr'),
                  onTap: () async {
                    final label = await _textInput('Custom dhikr');
                    if (label != null) _store.addCustom(label);
                  },
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) => Scaffold(
        backgroundColor: p.scaffold,
        appBar: AppBar(
          title: const Text('Tasbeeh'),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'Tasbeeh settings',
              onPressed: _store.ready ? _settings : null,
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: !_store.ready
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                  builder: (context, box) {
                    final deviceWidth = (box.maxHeight - 143) * 340 / 460;
                    return SingleChildScrollView(
                      child: Center(
                        child: Column(
                          children: [
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              child: TextButton.icon(
                                onPressed: _selector,
                                icon: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 20,
                                ),
                                label: Text(
                                  _store.selected.label,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: p.text,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: deviceWidth
                                  .clamp(250.0, 370.0)
                                  .clamp(0.0, box.maxWidth - 24),
                              child: TasbeehCounter(
                                value: _store.display,
                                onCount: _count,
                                onUndo: _store.undo,
                                onReset: _reset,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Tap to count',
                              style: TextStyle(
                                color: p.muted,
                                fontSize: 13,
                                letterSpacing: .5,
                              ),
                            ),
                            if (_store.target != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  'Target ${_store.target}',
                                  style: TextStyle(
                                    color: p.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            if (_store.saveError != null)
                              TextButton(
                                onPressed: () async {
                                  await _store.flush();
                                  if (mounted) setState(() {});
                                },
                                child: Text(_store.saveError!),
                              ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
