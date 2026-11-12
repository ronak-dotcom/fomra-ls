import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_ls/services/offline_sync_service.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('no / weak signal is queued', () {
    expect(OfflineSyncService.isNetworkError(TimeoutException('slow')), isTrue);
    expect(OfflineSyncService.isNetworkError(ClientException('Failed to fetch')),
        isTrue);
    expect(
        OfflineSyncService.isNetworkError(
            const PostgrestException(message: 'Failed to fetch')),
        isTrue);
    expect(OfflineSyncService.isNetworkError(Exception('SocketException: x')),
        isTrue);
  });

  test('a refusal from the database is shown, not queued', () {
    expect(
        OfflineSyncService.isNetworkError(const PostgrestException(
            message: 'new row violates row-level security policy',
            code: '42501')),
        isFalse);
    expect(OfflineSyncService.isNetworkError(ArgumentError('bad')), isFalse);
  });
}
