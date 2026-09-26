import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:solwatt/network.dart';

/// Minimal replacement for Solian's drift-backed [AppDatabase]. The drive
/// only uses `setSecret`/`getSecret` (E2EE file-key storage), so this wraps
/// the existing secure storage instead of pulling in the drift stack.
class AppDatabase {
  AppDatabase(this._storage);

  final FlutterSecureStorage _storage;

  Future<void> setSecret(String key, String value) =>
      _storage.write(key: key, value: value);

  Future<String?> getSecret(String key) => _storage.read(key: key);
}

final databaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase(ref.watch(secureStorageProvider));
});
