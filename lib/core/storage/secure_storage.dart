// Secure storage for sensitive data such as API keys and dashboard credentials.
//
// Uses flutter_secure_storage which delegates to:
//   - Android: EncryptedSharedPreferences / KeyStore
//   - iOS: Keychain
//
// API keys are never stored in plaintext SharedPreferences.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps [FlutterSecureStorage] to provide a simple key-value interface
/// for secrets such as API keys and dashboard passwords.
class SecureStorage {
  final FlutterSecureStorage _storage;

  SecureStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage(
          aOptions: AndroidOptions(
            encryptedSharedPreferences: true,
          ),
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.first_unlock,
          ),
        );

  /// Reads a secret value. Returns null if the key does not exist.
  Future<String?> read(String key) async {
    return _storage.read(key: key);
  }

  /// Writes a secret value. If [value] is null or empty, deletes the key
  /// instead of storing an empty string.
  Future<void> write(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await _storage.delete(key: key);
      return;
    }
    await _storage.write(key: key, value: value);
  }

  /// Deletes a secret value if it exists.
  Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }

  /// Deletes all keys matching the given prefix.
  Future<void> deleteAllWithPrefix(String prefix) async {
    final all = await _storage.readAll();
    for (final key in all.keys) {
      if (key.startsWith(prefix)) {
        await _storage.delete(key: key);
      }
    }
  }

  // ── Convenience helpers for per-connection secrets ──────────────────

  /// Storage key for a connection's API key.
  static String apiKeyKey(String connectionId) => 'conn_$connectionId.api_key';

  /// Storage key for a connection's dashboard username.
  static String dashUserKey(String connectionId) =>
      'conn_$connectionId.dash_user';

  /// Storage key for a connection's dashboard password.
  static String dashPassKey(String connectionId) =>
      'conn_$connectionId.dash_pass';

  /// Stores all secrets for a connection.
  Future<void> writeConnectionSecrets({
    required String connectionId,
    String? apiKey,
    String? dashboardUsername,
    String? dashboardPassword,
  }) async {
    await write(apiKeyKey(connectionId), apiKey);
    await write(dashUserKey(connectionId), dashboardUsername);
    await write(dashPassKey(connectionId), dashboardPassword);
  }

  /// Reads the API key for a connection.
  Future<String?> readApiKey(String connectionId) =>
      read(apiKeyKey(connectionId));

  /// Reads dashboard credentials for a connection.
  Future<({String? username, String? password})> readDashboardCredentials(
    String connectionId,
  ) async {
    final username = await read(dashUserKey(connectionId));
    final password = await read(dashPassKey(connectionId));
    return (username: username, password: password);
  }

  /// Deletes all secrets for a connection.
  Future<void> deleteConnectionSecrets(String connectionId) async {
    await delete(apiKeyKey(connectionId));
    await delete(dashUserKey(connectionId));
    await delete(dashPassKey(connectionId));
  }
}
