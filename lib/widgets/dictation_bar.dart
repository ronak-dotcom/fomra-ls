import 'package:flutter/material.dart';

import '../services/dictation.dart';
import '../theme/app_theme.dart';
import '../theme/fomra_theme_context.dart';

/// Max characters for notes boxes (meeting notes, lead notes, signed and
/// legal notes, reviews, drop notes).
const kNotesMaxLength = 5000;

/// Speak-to-type under a notes box: a mic and, while listening, the words
/// being heard. English only — notes are kept in English. Finished phrases
/// go into [controller] where the cursor is. Hidden where the browser has no
/// speech recognition.
class DictationBar extends StatefulWidget {
  final TextEditingController controller;
  final int maxLength;

  /// Starts listening as soon as it is shown (voice note recorder).
  final bool autoStart;

  /// Told when listening starts / stops, and of any error code.
  final ValueChanged<bool>? onListening;
  final ValueChanged<String>? onError;

  const DictationBar({
    super.key,
    required this.controller,
    this.maxLength = kNotesMaxLength,
    this.autoStart = false,
    this.onListening,
    this.onError,
  });

  @override
  State<DictationBar> createState() => DictationBarState();
}

class DictationBarState extends State<DictationBar> {
  DictationSession? _session;
  String _interim = '';
  String? _error;

  bool get listening => _session != null;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) start();
      });
    }
  }

  void start() {
    if (listening || !Dictation.isSupported) return;
    setState(() {
      _error = null;
      _interim = '';
    });
    _session = Dictation.start(
      lang: Dictation.language,
      onFinal: _insert,
      onInterim: (t) {
        if (mounted) setState(() => _interim = t);
      },
      onDone: (error) {
        if (!mounted) return;
        setState(() {
          _session = null;
          _interim = '';
          _error = error == null ? null : Dictation.messageFor(error);
        });
        widget.onListening?.call(false);
        if (error != null) widget.onError?.call(error);
      },
    );
    widget.onListening?.call(true);
  }

  void stop() => _session?.stop();

  /// Puts [text] at the cursor (or the end), with a space before it when
  /// needed and a capital at the start of a sentence; never past the limit.
  void _insert(String text) {
    final c = widget.controller;
    final value = c.text;
    var at = c.selection.isValid ? c.selection.start : value.length;
    if (at < 0 || at > value.length) at = value.length;
    final before = value.substring(0, at);
    final after = value.substring(at);
    final trimmedBefore = before.trimRight();
    final sentenceStart = trimmedBefore.isEmpty ||
        RegExp(r'[.!?\n]$').hasMatch(trimmedBefore);
    var piece = text.trim();
    if (piece.isEmpty) return;
    if (sentenceStart) {
      piece = piece[0].toUpperCase() + piece.substring(1);
    }
    final needsSpace = before.isNotEmpty && !RegExp(r'\s$').hasMatch(before);
    piece = '${needsSpace ? ' ' : ''}$piece';
    final room = widget.maxLength - value.length;
    if (room <= 0) return;
    if (piece.length > room) piece = piece.substring(0, room);
    final next = '$before$piece$after';
    c.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: before.length + piece.length),
    );
  }

  @override
  void dispose() {
    _session?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Dictation.isSupported) return const SizedBox.shrink();
    final on = listening;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Material(
              color: on
                  ? AppColors.error
                  : AppColors.primary.withValues(alpha: 0.10),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: on ? stop : start,
                child: Padding(
                  padding: const EdgeInsets.all(9),
                  child: Icon(on ? Icons.stop_rounded : Icons.mic_none_rounded,
                      size: 20, color: on ? Colors.white : AppColors.primary),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (on)
              Expanded(
                child: Text(
                  _interim.isEmpty ? 'Listening… tap to stop' : _interim,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: _interim.isEmpty ? FontWeight.w700 : null,
                    color: _interim.isEmpty
                        ? AppColors.error
                        : context.fomraTextSecondary,
                  ),
                ),
              )
            else
              Flexible(
                child: Text('Tap the mic and speak in English',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: context.fomraTextTertiary)),
              ),
          ]),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_error!,
                  style: const TextStyle(fontSize: 12, color: AppColors.error)),
            ),
        ],
      ),
    );
  }
}
