import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionManager {
  static final _storage = FlutterSecureStorage();
  static const _currentUserKey = 'current_user_id';

  // Store a user's token with their userId as the key
  static Future<void> saveToken(String userId, String token) async {
    await _storage.write(key: userId, value: token);
  }

  // Retrieve a user's token by userId
  static Future<String?> getToken(String userId) async {
    return await _storage.read(key: userId);
  }

  // Remove a user's token by userId
  static Future<void> clearToken(String userId) async {
    await _storage.delete(key: userId);
  }

  static Future<bool> isLoggedIn(String userId) async {
    final token = await getToken(userId);
    return token != null && token.isNotEmpty;
  }

  static Future<void> setCurrentUser(String userId) async {
    await _storage.write(key: _currentUserKey, value: userId);
  }

  static Future<String?> getCurrentUser() async {
    return await _storage.read(key: _currentUserKey);
  }

  static Future<void> clearCurrentUser() async {
    await _storage.delete(key: _currentUserKey);
  }
}