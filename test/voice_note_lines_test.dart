import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_ls/services/voice_note_service.dart';
import 'package:fomra_ls/utils/note_time.dart';

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

  test('the topic is shown and read back', () {
    final line = VoiceNoteService.notesLine(
        at: at, audioRef: 'p', durationMs: 16000, loggedBy: 'Management',
        topic: 'site_visit', transcript: 'Road is 30 feet');
    expect(line,
        '[19 Nov 2026, 10:12] [Voice Note] audio:p · Site visit · 16s · Management · "Road is 30 feet"');
    expect(VoiceNoteService.topicOf(line), 'Site visit');
    expect(VoiceNoteService.displayLine(line),
        '[19 Nov 2026, 10:12] Site visit · 16s · Management · "Road is 30 feet"');
    expect(VoiceNoteService.topicOf('[1 Oct 2026, 09:00] [Voice Note] audio:x · 12s'), isNull);
  });

  test('notes are placed at the time they were written', () {
    expect(noteEntryTime('[20/11/2026 13:03] Called owner'), DateTime(2026, 11, 20, 13, 3));
    expect(noteEntryTime('[3/9/2026 8:05] x'), DateTime(2026, 9, 3, 8, 5));
    expect(noteEntryTime('[20 Nov 2026, 13:03] [Voice Note] audio:p · 16s'),
        DateTime(2026, 11, 20, 13, 3));
    expect(noteEntryTime('[Location Intelligence]'), isNull);
    expect(noteEntryTime('plain text'), isNull);
  });
}
