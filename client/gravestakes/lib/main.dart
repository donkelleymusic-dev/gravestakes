import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'game.dart';
import 'login_screen.dart';
import 'main_menu.dart';
import 'splash_screen.dart'; 

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://rbpmgzcafsykjbljgfvl.supabase.co', 
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJicG1nemNhZnN5a2pibGpnZnZsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY5MzEzMTgsImV4cCI6MjEwMjUwNzMxOH0.z-Th0EOWSqr4M7UcDrZUNO4U_ylhJ_nVB0VcUPWAYHA',
  );
  
  runApp(const GraveStakesApp());
}

class GraveStakesApp extends StatelessWidget {
  const GraveStakesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lumen Breach', 
      theme: ThemeData.dark(),
      home: const SplashScreen(), 
    );
  }
}

class AuthGatekeeper extends StatefulWidget {
  const AuthGatekeeper({super.key});

  @override
  State<AuthGatekeeper> createState() => _AuthGatekeeperState();
}

class _AuthGatekeeperState extends State<AuthGatekeeper> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        
        final session = snapshot.data?.session ?? Supabase.instance.client.auth.currentSession;
        
        // THE PREVENTION: If they have a session, but it is actively expired,
        // show the spinner! Supabase is fetching a new token in the background,
        // and will emit a new stream event when it succeeds (or fails).
        if (session != null && session.isExpired) {
          return const Center(child: CircularProgressIndicator());
        }
        
        // Token is alive and well! Let them in.
        if (session != null) {
          return const MainMenuScreen();
        }
        
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        return const LoginScreen();
      },
    );
  }
}