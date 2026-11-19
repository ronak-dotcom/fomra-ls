import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'dictation.dart';

/// Chrome and Safari only expose the prefixed constructor.
JSFunction? _ctor() {
  for (final name in ['SpeechRecognition', 'webkitSpeechRecognition']) {
    if (globalContext.has(name)) {
      final c = globalContext[name];
      if (c != null && c.typeofEquals('function')) return c as JSFunction;
    }
  }
  return null;
}

bool dictationSupported() => _ctor() != null;

bool get _isAndroid =>
    web.window.navigator.userAgent.toLowerCase().contains('android');

DictationSession startDictation({
  required String lang,
  required void Function(String text) onFinal,
  void Function(String text)? onInterim,
  required void Function(String? error) onDone,
}) {
  final ctor = _ctor();
  if (ctor == null) {
    onDone('unsupported');
    return _WebSession._dead();
  }
  return _WebSession(ctor, lang, onFinal, onInterim, onDone).._begin();
}

/// Android Chrome repeats earlier words in continuous mode, so there each
/// phrase is its own short session, restarted until [stop]; elsewhere one
/// continuous session (also restarted if the browser ends it early).
class _WebSession implements DictationSession {
  final JSFunction? _ctorFn;
  final String _lang;
  final void Function(String) _onFinal;
  final void Function(String)? _onInterim;
  final void Function(String?) _onDone;

  web.SpeechRecognition? _rec;
  bool _wanted = true;
  bool _done = false;
  String? _error;
  int _restarts = 0;

  _WebSession(this._ctorFn, this._lang, this._onFinal, this._onInterim,
      this._onDone);

  _WebSession._dead()
      : _ctorFn = null,
        _lang = '',
        _onFinal = _ignore,
        _onInterim = null,
        _onDone = _ignoreDone,
        _wanted = false,
        _done = true;

  static void _ignore(String _) {}
  static void _ignoreDone(String? _) {}

  void _begin() {
    final ctor = _ctorFn;
    if (ctor == null || !_wanted) return;
    final rec = ctor.callAsConstructor<web.SpeechRecognition>();
    rec.lang = _lang;
    rec.continuous = !_isAndroid;
    rec.interimResults = true;
    rec.onresult = ((web.SpeechRecognitionEvent e) {
      final results = e.results;
      var interim = '';
      for (var i = e.resultIndex; i < results.length; i++) {
        final r = results.item(i);
        if (r.length == 0) continue;
        final text = r.item(0).transcript.trim();
        if (text.isEmpty) continue;
        if (r.isFinal) {
          _onFinal(text);
        } else {
          interim = interim.isEmpty ? text : '$interim $text';
        }
      }
      _onInterim?.call(interim);
    }).toJS;
    rec.onerror = ((web.SpeechRecognitionErrorEvent e) {
      _error = e.error;
    }).toJS;
    rec.onend = ((web.Event _) {
      _onInterim?.call('');
      final err = _error;
      _error = null;
      // Silence ends a session: keep listening until the user taps stop.
      final keepGoing = _wanted &&
          (err == null || err == 'no-speech' || err == 'aborted') &&
          _restarts < 500;
      if (keepGoing) {
        _restarts++;
        Timer(const Duration(milliseconds: 120), _begin);
      } else {
        _finish(err == 'no-speech' || err == 'aborted' ? null : err);
      }
    }).toJS;
    _rec = rec;
    try {
      rec.start();
    } catch (_) {
      _finish('audio-capture');
    }
  }

  void _finish(String? error) {
    if (_done) return;
    _done = true;
    _wanted = false;
    _onDone(error);
  }

  @override
  void stop() {
    if (!_wanted) return;
    _wanted = false;
    try {
      _rec?.stop();
    } catch (_) {
      _finish(null);
    }
    // Some browsers never fire `end` after stop; make sure it finishes.
    Timer(const Duration(seconds: 2), () => _finish(null));
  }
}
