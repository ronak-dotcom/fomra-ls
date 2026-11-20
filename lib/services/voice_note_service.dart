import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_store.dart';
import 'auth_service.dart';
import 'land_lead_service.dart';
import 'offline_sync_service.dart';

/// Voice notes on a lead: the audio (private bucket — played through a
/// short-lived link), the text written while speaking, and one line in the
/// lead's notes that the timeline shows:
///
///   [19 Nov 2026, 10:12] [Voice Note] audio:<path> · 42s · Saurabh · "text"
///
/// Older lines carry a full public URL after `audio:` and still play.
class VoiceNoteService {
  static SupabaseClient get _db => Supabase.instance.client;
  static const bucket = 'land-lead-voice-notes';

  /// Uploads the audio, records it, and adds the line to the lead's notes.
  static Future<void> uploadAndAttach({
    required String leadId,
    required Uint8List bytes,
    required int durationMs,
    String transcript = '',
    String ext = 'm4a',
  }) async {
    final userId = _db.auth.currentUser?.id;
    final loggedBy = AuthService.instance.currentUser?.fullName ?? '';
    final safeExt = RegExp(r'^[a-z0-9]{2,5}$').hasMatch(ext) ? ext : 'm4a';
    final path =
        '$leadId/${DateTime.now().millisecondsSinceEpoch}_voice.$safeExt';

    await _db.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentTypeFor(safeExt),
            upsert: true,
          ),
        );

    final text = transcript.trim();
    try {
      await _db.from('land_lead_voice_notes').insert({
        'lead_id': leadId,
        'storage_path': path,
        'duration_ms': durationMs,
        'transcript': text,
        if (loggedBy.isNotEmpty) 'logged_by_name': loggedBy,
        if (userId != null) 'logged_by': userId,
      });
    } catch (_) {
      // The notes line below is what the timeline reads; this is the index.
    }

    final lead =
        AppStore.instance.leads.where((l) => l.leadId == leadId).firstOrNull;
    if (lead != null) {
      final line = notesLine(
        at: DateTime.now(),
        audioRef: path,
        durationMs: durationMs,
        loggedBy: loggedBy,
        transcript: text,
      );
      final notes = _withoutQueuedLine(lead.notes);
      final updated = await LandLeadService.update(lead.copyWith(
          notes: notes.trim().isEmpty ? line : '${notes.trim()}\n$line'));
      AppStore.instance.replaceLead(updated);
    }
  }

  /// One notes line for a voice note (the text kept on one line).
  static String notesLine({
    required DateTime at,
    required String? audioRef,
    required int durationMs,
    String loggedBy = '',
    String transcript = '',
    bool queued = false,
  }) {
    final stamp = DateFormat('d MMM yyyy, HH:mm').format(at);
    final secs = (durationMs / 1000).round();
    final text = transcript.replaceAll(RegExp(r'\s+'), ' ').trim();
    return [
      '[$stamp] [Voice Note]${audioRef == null ? '' : ' audio:$audioRef'}',
      if (queued) 'waiting to upload',
      '${secs}s',
      if (loggedBy.isNotEmpty) loggedBy,
      if (text.isNotEmpty) '"$text"',
    ].join(' · ');
  }

  static const _queuedMarker = '[Voice Note] · waiting to upload';

  /// The placeholder line added while offline, removed once uploaded.
  static String _withoutQueuedLine(String notes) => notes
      .split('\n')
      .where((l) => !l.contains(_queuedMarker))
      .join('\n');

  /// Saves now, or keeps it on the phone and uploads when back online.
  static Future<void> saveOfflineOrUpload({
    required String leadId,
    required Uint8List bytes,
    required int durationMs,
    String transcript = '',
    String ext = 'm4a',
  }) async {
    final sync = OfflineSyncService.instance;
    if (!sync.isOnline) {
      await sync.enqueueVoiceNote(
        leadId: leadId,
        bytes: bytes,
        durationMs: durationMs,
        transcript: transcript,
        ext: ext,
      );
      final lead =
          AppStore.instance.leads.where((l) => l.leadId == leadId).firstOrNull;
      if (lead != null) {
        final line = notesLine(
          at: DateTime.now(),
          audioRef: null,
          durationMs: durationMs,
          loggedBy: AuthService.instance.currentUser?.fullName ?? '',
          transcript: transcript,
          queued: true,
        );
        final notes =
            lead.notes.trim().isEmpty ? line : '${lead.notes.trim()}\n$line';
        AppStore.instance.replaceLead(lead.copyWith(notes: notes));
      }
      return;
    }
    await uploadAndAttach(
      leadId: leadId,
      bytes: bytes,
      durationMs: durationMs,
      transcript: transcript,
      ext: ext,
    );
  }

  static String contentTypeFor(String ext) => switch (ext.toLowerCase()) {
        'wav' => 'audio/wav',
        'mp3' => 'audio/mpeg',
        'webm' => 'audio/webm',
        'ogg' || 'opus' => 'audio/ogg',
        _ => 'audio/mp4',
      };

  /// What follows `audio:` in a notes line: a storage path, or (older
  /// lines) a full URL.
  static String? audioRefFromNotesLine(String line) =>
      RegExp(r'audio:(\S+)').firstMatch(line)?.group(1);

  /// A link that plays [ref] for an hour (private audio), or [ref] itself
  /// when it is already a URL.
  static Future<String?> playableUrl(String ref) async {
    if (ref.startsWith('http://') || ref.startsWith('https://')) return ref;
    try {
      return await _db.storage.from(bucket).createSignedUrl(ref, 3600);
    } catch (_) {
      return null;
    }
  }

  /// A voice note line for reading: without the tag and the audio link.
  /// "[19 Nov 2026, 10:12] 42s · Saurabh · "text"".
  static String displayLine(String line) => line
      .replaceFirst(RegExp(r'\s*\[Voice Note\]'), '')
      .replaceFirst(RegExp(r'\s*audio:\S+'), '')
      .replaceFirst(RegExp(r'\]\s*·\s*'), '] ')
      .trim();
}
