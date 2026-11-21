import 'dictation_stub.dart'
    if (dart.library.html) 'dictation_web.dart' as impl;

/// A running speak-to-type session; [stop] ends it (the last words still
/// arrive through `onFinal`, then `onDone`).
abstract interface class DictationSession {
  void stop();
}

/// Speak-to-type in English with the browser's own speech recognition
/// (Chrome on Android / desktop, Safari on iPhone): free, needs internet,
/// keeps no audio. Unsupported browsers report [isSupported] false and the mic is
/// hidden.
abstract final class Dictation {
  /// Notes are kept in English only: the mic always listens for English
  /// (Indian accent). Voice note audio itself can be in any language.
  static const language = 'en-IN';

  static bool get isSupported => impl.dictationSupported();

  /// Starts listening in [lang]. [onFinal] gets each finished phrase,
  /// [onInterim] the words still being heard ('' when none), and [onDone]
  /// fires once when listening ends — with an error code ('not-allowed',
  /// 'network', 'audio-capture', 'language-not-supported', …) or null.
  static DictationSession start({
    required String lang,
    required void Function(String text) onFinal,
    void Function(String text)? onInterim,
    required void Function(String? error) onDone,
  }) =>
      impl.startDictation(
        lang: lang,
        onFinal: onFinal,
        onInterim: onInterim,
        onDone: onDone,
      );

  /// A short message for a recognition error code.
  static String messageFor(String error) => switch (error) {
        'not-allowed' || 'service-not-allowed' =>
          'Allow the microphone for this site in the browser settings.',
        'network' => 'Speak-to-type needs an internet connection.',
        'audio-capture' => 'The microphone is busy or not available.',
        'language-not-supported' =>
          "This phone's speech service doesn't support English (India).",
        'unsupported' => "This browser doesn't support speak-to-type.",
        _ => 'Speak-to-type stopped ($error). Tap the mic to try again.',
      };
}
