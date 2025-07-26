import 'package:flutter/material.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import '../auth/auth.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final Auth _auth = Auth();
  String _phoneNumber = '';
  bool _loading = false;
  String? _error;

  Future<void> _handleLoginButtonPress() async {
    final phone = _phoneNumber.trim();
    
    // Check if phone number is entered
    if (phone.isEmpty) {
      setState(() {
        _error = 'Enter your phone number';
      });
      return;
    }

    // Send SMS directly
    await _sendSMS(phone);
  }

  Future<void> _sendSMS(String phone) async {
    try {
      // Show loading immediately
      setState(() {
        _loading = true;
        _error = null;
      });
      
      // Move auth call off main thread
      await Future.microtask(() => _auth.login(phone));
      
      if (mounted) {
        Navigator.pushNamed(context, '/otp', arguments: phone);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to send SMS: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IntlPhoneField(
                decoration: const InputDecoration(labelText: 'Phone Number'),
                initialCountryCode: 'US',
                onChanged: (phone) {
                  _phoneNumber = phone.completeNumber;
                },
                // Remove heavy validation that runs on every keystroke
                validator: null,
              ),
              const SizedBox(height: 20),
              
              if (_error != null) ...[
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
              ],
              
              _loading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _handleLoginButtonPress,
                      child: const Text('Send Code'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}