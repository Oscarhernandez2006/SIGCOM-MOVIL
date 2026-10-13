import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Credenciales recordadas en el almacenamiento cifrado del dispositivo (Android Keystore / iOS Keychain).
class CredentialsStore {
  CredentialsStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  static const _documentKey = 'saved_document';
  static const _passwordKey = 'saved_password';

  final FlutterSecureStorage _storage;

  Future<({String document, String password})?> read() async {
    final document = await _storage.read(key: _documentKey);
    final password = await _storage.read(key: _passwordKey);
    if (document == null || password == null) return null;
    return (document: document, password: password);
  }

  Future<void> save(String document, String password) async {
    await _storage.write(key: _documentKey, value: document);
    await _storage.write(key: _passwordKey, value: password);
  }

  Future<void> clear() async {
    await _storage.delete(key: _documentKey);
    await _storage.delete(key: _passwordKey);
  }
}
