import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'game.dart';
import 'login_screen.dart';
import 'main_menu.dart';
import 'splash_screen.dart'; // Make sure this is here!

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    // FIXED: Removed /rest/v1/ from the URL
    url: 'https://rbpmgzcafsykjbljgfvl.supabase.co', 
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJicG1nemNhZnN5a2pibGpnZnZsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY5MzEzMTgsImV4cCI6MjEwMjUwNzMxOH0.z-Th0EOWSqr4M7UcDrZUNO4U_ylhJ_nVB0VcUPWAYHA',
  );
  
   // await Supabase.instance.client.auth.signOut();
  runApp(const GraveStakesApp());
}

class GraveStakesApp extends StatelessWidget {
  const GraveStakesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lumen Breach', // Updated the name here
      theme: ThemeData.dark(),
      home: const SplashScreen(), // CHANGED: We now start at the Splash Screen!
    );
  }
}

// The Gatekeeper listens for login/logout events in real-time
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
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final session = snapshot.data?.session;
        
        // If they have a session, boot up the Main Menu!
        if (session != null) {
          return const MainMenuScreen();
        }
        
        // Otherwise, show the Login UI
        return const LoginScreen();
      },
    );
  }
}