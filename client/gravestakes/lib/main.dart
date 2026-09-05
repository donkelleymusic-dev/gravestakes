import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';

// --- NEW IMPORTS FOR PAYMENTS ---
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'dart:io' show Platform; // For Platform checks
import 'package:purchases_flutter/purchases_flutter.dart';
// --------------------------------

import 'game.dart';
import 'login_screen.dart';
import 'main_menu.dart';
import 'splash_screen.dart';
import 'audio_manager.dart';

Future<void> main() async {
  // 1. Ensure Flutter engine bindings are ready for async tasks before runApp
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://rbpmgzcafsykjbljgfvl.supabase.co', 
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJicG1nemNhZnN5a2pibGpnZnZsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY5MzEzMTgsImV4cCI6MjEwMjUwNzMxOH0.z-Th0EOWSqr4M7UcDrZUNO4U_ylhJ_nVB0VcUPWAYHA',
  );

  // --- 2. REVENUECAT INITIALIZATION ---
  // Guard against web builds since StoreKit/Google Play Billing don't exist in browsers
  if (!kIsWeb) {
    await Purchases.setLogLevel(LogLevel.debug);

    if (Platform.isIOS) {
      await Purchases.configure(PurchasesConfiguration("appl_aJcMjydRQhDoZUvQpUjQgNpLPyH")); 
    } else if (Platform.isAndroid) {
      await Purchases.configure(PurchasesConfiguration("goog_NvbOeRUARSAPSunHAVZSjcKjoWE"));
    }
  }
  // ------------------------------------

  // 3. Initialize SoLoud and fire the music immediately during the splash phase
  await AudioManager.instance.init();
  AudioManager.instance.playMenuMusic();

  // 4. Make game full screen
  // Hide the navigation bar (Back/Home/Recents) and status bar automatically
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
  );

  // Allow all device orientations (portrait, landscape, and inverted)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // 5. Boot the visual app
  runApp(const GraveStakesApp());
}

// Convert GraveStakesApp to a StatefulWidget to hold the lifecycle listener
class GraveStakesApp extends StatefulWidget {
  const GraveStakesApp({super.key});

  @override
  State<GraveStakesApp> createState() => _GraveStakesAppState();
}

class _GraveStakesAppState extends State<GraveStakesApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();

    // Hook into Android/iOS OS-level background events
    _lifecycleListener = AppLifecycleListener(
      onPause: () => AudioManager.instance.mute(),
      onInactive: () => AudioManager.instance.mute(),
      onResume: () => AudioManager.instance.unmute(),
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

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