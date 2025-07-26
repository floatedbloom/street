import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class Auth {
  final GoTrueClient _auth = Supabase.instance.client.auth;
  static Future<void> intialize() async {
    await dotenv.load();
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL'] ?? '',
      anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
    );
  }

  Future<void> login(String phone) async {
    try {
      await _auth.signInWithOtp(
        phone: phone,
      );
    } on AuthException catch (e) {
      throw Exception('Login failed: ${e.message}');
    } catch (e) {
      throw Exception('Unexpected error: $e');
    }
  }

  Future<void> verify(String phone, String otp) async {
    try {
      await _auth.verifyOTP(
        phone: phone,
        token: otp,
        type: OtpType.sms,
      );
    } on AuthException catch (e) {
      throw Exception('Verification failed: ${e.message}');
    } catch (e) {
      throw Exception('Unexpected error: $e');
    }
  }

  Future<void> logout() async {
    try {
      await _auth.signOut();
    } catch (e) {
      throw Exception('Logout failed: $e');
    }
  }

  Future<void> updateNumber(String phone) async {
    try {
      await _auth.updateUser(UserAttributes(phone: phone));
    } on AuthException catch (e) {
      throw Exception('Update number failed: ${e.message}');
    } catch (e) {
      throw Exception('Unexpected error: $e');
    }
  }
}