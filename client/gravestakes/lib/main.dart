import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:easy_localization/easy_localization.dart'; 

// --- NEW IMPORTS FOR PAYMENTS ---
import 'package:flutter/foundation.dart'; 
import 'dart:io' show Platform; 
import 'package:purchases_flutter/purchases_flutter.dart';
// --------------------------------

import 'game.dart';
import 'login_screen.dart';
import 'main_menu.dart';
import 'splash_screen.dart';
import 'audio_manager.dart';

Future<void> main() async {
  // 1. MUST BE FIRST: Ensure Flutter bindings and localization are ready before Sentry boots
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  // 2. Initialize Sentry
  await SentryFlutter.init(
    (options) {
      options.dsn = 'https://5c13105a06c0c151b3fab20c9ad12475@o4511748451729408.ingest.us.sentry.io/4512048891428864'; 
      options.tracesSampleRate = 1.0; 
    },
    appRunner: () async {
      await Supabase.initialize(
        url: 'https://rbpmgzcafsykjbljgfvl.supabase.co', 
        anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJicG1nemNhZnN5a2pibGpnZnZsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY5MzEzMTgsImV4cCI6MjEwMjUwNzMxOH0.z-Th0EOWSqr4M7UcDrZUNO4U_ylhJ_nVB0VcUPWAYHA',
      );

      // --- 3. REVENUECAT INITIALIZATION ---
      if (!kIsWeb) {
        await Purchases.setLogLevel(LogLevel.debug);
        if (Platform.isIOS) {
          await Purchases.configure(PurchasesConfiguration("appl_aJcMjydRQhDoZUvQpUjQgNpLPyH")); 
        } else if (Platform.isAndroid) {
          await Purchases.configure(PurchasesConfiguration("goog_NvbOeRUARSAPSunHAVZSjcKjoWE"));
        }
      }

      // 4. Audio & Display settings
      await AudioManager.instance.init();
      AudioManager.instance.playMenuMusic();

      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
      );

      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

      // 5. Wrap the app with EasyLocalization
      runApp(
        EasyLocalization(
          supportedLocales: const [
            Locale('en'), Locale('es'), Locale('ja'), Locale('de'),
          ],
          path: 'assets/translations', // Ensure this folder and your .json files exist
          fallbackLocale: const Locale('en'),
          child: const GraveStakesApp(),
        ),
      );
    },
  );
}

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
    // --- NEW: Safe Localization Fallback ---
    // If the translations fail to load, this prevents the fatal crash by defaulting to standard Flutter English
    Iterable<LocalizationsDelegate<dynamic>>? delegates;
    Iterable<Locale>? supportedLocales;
    Locale? currentLocale;
    
    try {
      delegates = context.localizationDelegates;
      supportedLocales = context.supportedLocales;
      currentLocale = context.locale;
    } catch (e) {
      debugPrint('Warning: Localization missing or not loaded. Defaulting to English. ($e)');
      supportedLocales = const [Locale('en')];
      currentLocale = const Locale('en');
    }

    return MaterialApp(
      localizationsDelegates: delegates,
      supportedLocales: supportedLocales ?? const [Locale('en')],
      locale: currentLocale,
      navigatorObservers: [
        SentryNavigatorObserver(),
      ],
      title: 'Lumen Breach', 
      theme: ThemeData.dark(),
      home: const AuthGatekeeper(), // Note: Routing to AuthGatekeeper to check login state 
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
        
        if (session != null && session.isExpired) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.purpleAccent)));
        }
        if (session != null) {
          return const MainMenuScreen();
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.purpleAccent)));
        }
        
        return const LoginScreen();
      },
    );
  }
}