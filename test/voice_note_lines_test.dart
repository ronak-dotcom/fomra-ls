import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_ls/services/voice_note_service.dart';

void main() {
  final at = DateTime(2026, 11, 19, 10, 12);

  test('a voice note line keeps the audio, length, who and the text', () {
    final line = VoiceNoteService.notesLine(
      at: at,
      audioRef: '134/1700_voice.m4a',
      durationMs: 42000,
      loggedBy: 'Saurabh',
      transcript: 'Owner ready to sell\\n8.64 acres',
    );
    expect(line,
        '[19 Nov 2026, 10:12] [Voice Note] audio:134/1700_voice.m4a · 42s · Saurabh · "Owner ready to sell\\n8.64 acres"');
    expect(VoiceNoteService.audioRefFromNotesLine(line), '134/1700_voice.m4a');
    expect(VoiceNoteService.displayLine(line),
        '[19 Nov 2026, 10:12] 42s · Saurabh · "Owner ready to sell\\n8.64 acres"');
  });

  test('the text is kept on one line', () {
    final line = VoiceNoteService.notesLine(
        at: at, audioRef: 'p', durationMs: 1000, transcript: 'one\ntwo  three');
    expect(line.contains('\n'), isFalse);
    expect(line.endsWith('"one two three"'), isTrue);
  });

  test('older lines with a full link still read and play', () {
    const old = '[1 Oct 2026, 09:00] [Voice Note] audio:https://x.supabase.co/a.m4a · 12s · Devaraj';
    expect(VoiceNoteService.audioRefFromNotesLine(old), 'https://x.supabase.co/a.m4a');
    expect(VoiceNoteService.displayLine(old), '[1 Oct 2026, 09:00] 12s · Devaraj');
  });

  test('queued offline: no audio yet', () {
    final line = VoiceNoteService.notesLine(
        at: at, audioRef: null, durationMs: 5000, queued: true);
    expect(VoiceNoteService.audioRefFromNotesLine(line), isNull);
    expect(VoiceNoteService.displayLine(line), '[19 Nov 2026, 10:12] waiting to upload · 5s');
  });
}
