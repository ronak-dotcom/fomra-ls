/// Names shown and saved with a capital at the start of every word:
/// "dinesh kumar" → "Dinesh Kumar", "k.mani" → "K.Mani",
/// "kalaiarasi(maheshwari)" → "Kalaiarasi(Maheshwari)". Only those first
/// letters change — anything already in capitals stays ("NRI", "McArthur").
///
/// The database applies the same rule on every save (public.cap_words), so
/// this keeps what the app shows in step with what is stored.
String capWords(String s) {
  if (s.isEmpty) return s;
  final out = StringBuffer();
  var startOfWord = true;
  for (final rune in s.runes) {
    final ch = String.fromCharCode(rune);
    out.write(startOfWord ? ch.toUpperCase() : ch);
    startOfWord = _wordBreak.hasMatch(ch);
  }
  return out.toString();
}

/// Characters after which a new word starts.
final _wordBreak = RegExp(r'[\s.(\[/,&+\-]');

/// [typed], capitalised — unless it is exactly what was already saved
/// ([saved]), so re-saving an untouched field never counts as a change.
String capWordsIfChanged(String typed, String? saved) =>
    saved != null && typed == saved.trim() ? typed : capWords(typed);
