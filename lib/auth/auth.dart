import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';

class Auth {
  final GoTrueClient _auth = Supabase.instance.client.auth;
  
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );
  
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
      final response = await _auth.verifyOTP(
        phone: phone,
        token: otp,
        type: OtpType.sms,
      );

      // After successful verification, save phone to people table
      final user = response.user;
      if (user != null) {
        await _savePhoneToPeopleTable(user.id, phone);
      }
    } on AuthException catch (e) {
      throw Exception('Verification failed: ${e.message}');
    } catch (e) {
      throw Exception('Unexpected error: $e');
    }
  }

  Future<void> _savePhoneToPeopleTable(String userId, String phone) async {
    try {
      final supabase = Supabase.instance.client;
      
      // Check if user profile exists
      final existingProfile = await supabase
          .from('people')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (existingProfile == null) {
        // Create new profile with phone number
        await supabase.from('people').insert({
          'id': userId,
          'phone': phone,
          'bio': <String, dynamic>{},
        });
      } else {
        // Update existing profile with phone number
        await supabase.from('people').update({
          'phone': phone,
        }).eq('id', userId);
      }
    } catch (e) {
      // Don't throw error here - login should still succeed even if phone save fails
      _logger.w('⚠️ Warning: Could not save phone to people table: $e');
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