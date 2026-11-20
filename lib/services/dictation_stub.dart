import 'dictation.dart';

bool dictationSupported() => false;

DictationSession startDictation({
  required String lang,
  required void Function(String text) onFinal,
  void Function(String text)? onInterim,
  required void Function(String? error) onDone,
}) {
  onDone('unsupported');
  return _NoSession();
}

class _NoSession implements DictationSession {
  @override
  void stop() {}
}
