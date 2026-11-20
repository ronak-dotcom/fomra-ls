import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../services/voice_note_service.dart';
import '../theme/app_theme.dart';
import '../theme/fomra_theme_context.dart';
import '../utils/voice_note_bytes.dart';
import 'dictation_bar.dart';

/// Record a voice note on a lead. The audio is kept, and while recording the
/// words are written out (free, the browser's own speech recognition) where
/// the phone allows both at once; otherwise the text can be spoken or typed
/// after stopping. Returns true when saved.
Future<bool?> showVoiceNoteRecorderDialog(
  BuildContext context, {
  required String leadId,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _VoiceNoteRecorderDialog(leadId: leadId),
  );
}

class _VoiceNoteRecorderDialog extends StatefulWidget {
  final String leadId;
  const _VoiceNoteRecorderDialog({required this.leadId});

  @override
  State<_VoiceNoteRecorderDialog> createState() =>
      _VoiceNoteRecorderDialogState();
}

class _VoiceNoteRecorderDialogState extends State<_VoiceNoteRecorderDialog> {
  static const _maxLength = Duration(minutes: 10);

  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  final _text = TextEditingController();
  final _dictation = GlobalKey<DictationBarState>();
  bool _recording = false;
  bool _saving = false;
  bool _liveTextFailed = false;
  String? _topic;
  bool _topicMissing = false;
  String? _error;
  String? _filePath;
  Uint8List? _bytes;
  String _ext = 'm4a';
  Duration _elapsed = Duration.zero;
  Timer? _tick;
  DateTime? _startedAt;

  @override
  void dispose() {
    _tick?.cancel();
    _recorder.dispose();
    _player.dispose();
    _text.dispose();
    super.dispose();
  }

  /// The best format this browser / phone can record: AAC (.m4a) plays
  /// everywhere; Chrome may only offer Opus (.webm).
  Future<(AudioEncoder, String)> _format() async {
    for (final (enc, ext) in const [
      (AudioEncoder.aacLc, 'm4a'),
      (AudioEncoder.opus, 'webm'),
      (AudioEncoder.wav, 'wav'),
    ]) {
      try {
        if (await _recorder.isEncoderSupported(enc)) return (enc, ext);
      } catch (_) {}
    }
    return (AudioEncoder.aacLc, 'm4a');
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _bytes = null;
      _filePath = null;
      _liveTextFailed = false;
      _elapsed = Duration.zero;
    });
    try {
      if (!await _recorder.hasPermission()) {
        setState(() => _error =
            'Allow the microphone for this site in the browser settings.');
        return;
      }
      final (encoder, ext) = await _format();
      _ext = ext;
      final path = await voiceNoteTempPath();
      await _recorder.start(RecordConfig(encoder: encoder), path: path);
      _startedAt = DateTime.now();
      _tick?.cancel();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_startedAt == null || !mounted) return;
        setState(() => _elapsed = DateTime.now().difference(_startedAt!));
        if (_elapsed >= _maxLength) _stop();
      });
      setState(() {
        _recording = true;
        _filePath = path;
      });
      // Write the words out while recording, where the phone allows it.
      _dictation.currentState?.start();
    } catch (e) {
      setState(() => _error = 'Could not start recording: $e');
    }
  }

  Future<void> _stop() async {
    _dictation.currentState?.stop();
    try {
      final path = await _recorder.stop();
      _tick?.cancel();
      final resolved = path ?? _filePath;
      Uint8List? bytes;
      if (resolved != null) bytes = await voiceNoteReadBytes(resolved);
      if (!mounted) return;
      setState(() {
        _recording = false;
        _filePath = resolved;
        _bytes = bytes;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recording = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _play() async {
    try {
      if (_bytes != null && _bytes!.isNotEmpty) {
        await _player.play(BytesSource(_bytes!, mimeType: VoiceNoteService.contentTypeFor(_ext)));
      } else if (_filePath != null) {
        await _player.play(DeviceFileSource(_filePath!));
      }
    } catch (e) {
      setState(() => _error = 'Playback failed: $e');
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    _dictation.currentState?.stop();
    var bytes = _bytes;
    if ((bytes == null || bytes.isEmpty) && _filePath != null) {
      bytes = await voiceNoteReadBytes(_filePath!);
    }
    if (bytes == null || bytes.isEmpty) {
      setState(() => _error = 'No recording to save.');
      return;
    }
    if (_topic == null) {
      setState(() => _topicMissing = true);
      return;
    }
    setState(() => _saving = true);
    try {
      await VoiceNoteService.saveOfflineOrUpload(
        leadId: widget.leadId,
        bytes: bytes,
        durationMs: _elapsed.inMilliseconds.clamp(500, 3600000),
        transcript: _text.text,
        topic: _topic!,
        ext: _ext,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save the voice note: $e';
      });
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final hasTake = (_bytes != null && _bytes!.isNotEmpty) ||
        (_filePath != null && !_recording);
    return AlertDialog(
      title: const Text('Voice note'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('What is this voice note about?',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _topicMissing
                        ? AppColors.error
                        : context.fomraTextSecondary,
                  )),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final (key, label) in VoiceNoteService.topics)
                  ChoiceChip(
                    label: Text(label, style: const TextStyle(fontSize: 12.5)),
                    selected: _topic == key,
                    onSelected: _saving
                        ? null
                        : (on) => setState(() {
                              _topic = on ? key : null;
                              _topicMissing = false;
                            }),
                  ),
              ]),
              if (_topicMissing)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Choose one before saving.',
                      style: TextStyle(fontSize: 12, color: AppColors.error)),
                ),
              const SizedBox(height: 16),
              Row(children: [
                Material(
                  color: _recording ? AppColors.error : AppColors.primary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _saving ? null : (_recording ? _stop : _start),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Icon(
                          _recording ? Icons.stop_rounded : Icons.mic_rounded,
                          size: 28,
                          color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_fmt(_elapsed),
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: _recording
                                ? AppColors.error
                                : context.fomraTextPrimary,
                          )),
                      Text(
                        _recording
                            ? 'Recording… tap to stop'
                            : hasTake
                                ? 'Recorded · tap the mic to record again'
                                : 'Tap the mic to record (up to 10 min)',
                        style: TextStyle(
                            fontSize: 12.5,
                            color: context.fomraTextSecondary),
                      ),
                    ],
                  ),
                ),
                if (hasTake && !_recording)
                  IconButton.filledTonal(
                    tooltip: 'Play',
                    onPressed: _play,
                    icon: const Icon(Icons.play_arrow_rounded),
                  ),
              ]),
              const SizedBox(height: 16),
              TextField(
                controller: _text,
                minLines: 3,
                maxLines: 8,
                maxLength: kNotesMaxLength,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'What was said',
                  hintText: 'Written as you speak — correct it if needed',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              DictationBar(
                key: _dictation,
                controller: _text,
                onError: (_) {
                  if (_recording && mounted) {
                    setState(() => _liveTextFailed = true);
                  }
                },
              ),
              if (_liveTextFailed)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    "This phone can't write the text while recording. The "
                    'audio is still recorded — after you stop, tap the small '
                    'mic to say a short summary, or type it.',
                    style: TextStyle(
                        fontSize: 12, color: context.fomraTextSecondary),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: const TextStyle(
                          color: AppColors.error, fontSize: 12.5)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: (_saving || _recording)
              ? null
              : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_saving || _recording || !hasTake) ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}
