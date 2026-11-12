import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

// Web: photos / voice notes queued offline go to IndexedDB, which holds
// hundreds of MB. The old home (base64 in localStorage, ~5 MB for the whole
// site) overflowed after a few site photos, and the offline save then failed
// and lost the lead. Blobs saved there before this change are still read.

const _dbName = 'fomra_offline';
const _store = 'blobs';
const _legacyPrefix = 'fomra_blob_v1_';

Future<web.IDBDatabase>? _db;

Future<T?> _await<T extends JSAny?>(web.IDBRequest req) {
  final c = Completer<T?>();
  req.onsuccess = ((web.Event _) => c.complete(req.result as T?)).toJS;
  req.onerror = ((web.Event _) =>
      c.completeError(StateError('IndexedDB: ${req.error?.message}'))).toJS;
  return c.future;
}

Future<web.IDBDatabase> _open() {
  return _db ??= () {
    final req = web.window.indexedDB.open(_dbName, 1);
    req.onupgradeneeded = ((web.Event _) {
      final db = req.result as web.IDBDatabase;
      if (!db.objectStoreNames.contains(_store)) {
        db.createObjectStore(_store);
      }
    }).toJS;
    return _await<web.IDBDatabase>(req).then((db) => db!);
  }();
}

web.IDBObjectStore _objectStore(web.IDBDatabase db, String mode) =>
    db.transaction(_store.toJS, mode).objectStore(_store);

Future<String> putBlob(Uint8List bytes, {String ext = 'bin'}) async {
  final id = 'b_${DateTime.now().microsecondsSinceEpoch}.$ext';
  final db = await _open();
  await _await<JSAny?>(
      _objectStore(db, 'readwrite').put(bytes.toJS, id.toJS));
  return id;
}

Future<Uint8List?> getBlob(String id) async {
  final db = await _open();
  final value =
      await _await<JSAny?>(_objectStore(db, 'readonly').get(id.toJS));
  if (value != null && value.isA<JSUint8Array>()) {
    return (value as JSUint8Array).toDart;
  }
  // Saved before the move to IndexedDB.
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('$_legacyPrefix$id');
  return raw == null ? null : Uint8List.fromList(base64Decode(raw));
}

Future<void> deleteBlob(String id) async {
  try {
    final db = await _open();
    await _await<JSAny?>(_objectStore(db, 'readwrite').delete(id.toJS));
  } catch (_) {}
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('$_legacyPrefix$id');
}
