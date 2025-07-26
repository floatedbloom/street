import 'package:flutter/material.dart';
import '../auth/auth.dart';

class OTPVerification extends StatefulWidget {
  final String phoneNumber;
  
  const OTPVerification({super.key, required this.phoneNumber});

  @override
  State<OTPVerification> createState() => _OTPVerificationState();
}

class _OTPVerificationState extends State<OTPVerification> {
  final Auth _auth = Auth();
  final TextEditingController _otpController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _verify() async {
    final otp = _otpController.text.trim();
    
    if (otp.length != 6) {
      setState(() {
        _error = 'Enter 6-digit code';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _auth.verify(widget.phoneNumber, otp);
      if (mounted) {
        Navigator.pushNamed(context, '/home');
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify Code')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Enter Verification Code',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Code sent to ${widget.phoneNumber}',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _otpController,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 24, letterSpacing: 8),
              decoration: const InputDecoration(
                hintText: '000000',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _verify,
                child: _loading 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Verify'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }
} 