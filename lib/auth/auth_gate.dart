import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../pages/login.dart';
import '../pages/home.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          final currentSession = Supabase.instance.client.auth.currentSession;
          if (currentSession != null) {
            return const Home();
          }
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        
        final session = snapshot.hasData ? snapshot.data!.session : null;
        if (session == null) {
          return const Login();
        } else {
          return const Home();
        }
      },
    );
  }
}