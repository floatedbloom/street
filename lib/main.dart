import 'package:flutter/material.dart';
import 'pages/login.dart';
import 'pages/home.dart';
import 'pages/otp_verification.dart';
import 'auth/auth.dart';
import 'auth/auth_gate.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Auth.intialize();
  
  // Initialize notifications
  try {
    await NotificationService.initialize();
  } catch (e) {
    print('Failed to initialize notifications: $e');
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: const AuthGate(),
      routes: {
        '/login': (context) => const Login(),
        '/home': (context) => const Home(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/otp') {
          final phone = settings.arguments as String;
          return MaterialPageRoute(
            builder: (context) => OTPVerification(phoneNumber: phone),
          );
        }
        return null;
      },
    );
  }
}