import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the IQM Resonance API token is kept. It never goes into the game
/// save or the settings file.
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> delete();
}

/// Keychain on iOS, Keystore-backed encryption on Android, WebCrypto on the
/// web.
class SecureTokenStore implements TokenStore {
  static const _key = 'qc.iqm.token';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this.token]);
  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String token) async => this.token = token;

  @override
  Future<void> delete() async => token = null;
}
