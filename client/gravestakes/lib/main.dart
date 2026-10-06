import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:easy_localization/easy_localization.dart'; 

// --- IMPORTS FOR PAYMENTS ---
import 'package:flutter/foundation.dart'; 
import 'dart:io' show Platform; 
import 'package:purchases_flutter/purchases_flutter.dart';

// --- NEW IMPORTS FOR GUEST PASS ROUTING ---
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
// --------------------------------

import 'package:app_tracking_transparency/app_tracking_transparency.dart';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'game.dart';
import 'login_screen.dart';
import 'main_menu.dart';
import 'splash_screen.dart';
import 'audio_manager.dart';

Future<void> main() async {
  // 1. Initialize Sentry first. This creates the custom error-tracking Zone.
  await SentryFlutter.init(
    (options) {
      options.dsn = 'https://5c13105a06c0c151b3fab20c9ad12475@o4511748451729408.ingest.us.sentry.io/4512048891428864'; 
      options.tracesSampleRate = 1.0; 
    },
    appRunner: () async {
      // 2. Initialize Flutter bindings INSIDE Sentry's zone
      WidgetsFlutterBinding.ensureInitialized();
      
      // 3. Initialize EasyLocalization INSIDE Sentry's zone
      await EasyLocalization.ensureInitialized();

      if (!kIsWeb) {
        // 1. Apple App Tracking Transparency (iOS Only)
        if (Platform.isIOS) {
          final status = await AppTrackingTransparency.trackingAuthorizationStatus;
          if (status == TrackingStatus.notDetermined) {
            // Short delay ensures the Flutter engine is fully attached before drawing the native pop-up
            await Future.delayed(const Duration(milliseconds: 500));
            await AppTrackingTransparency.requestTrackingAuthorization();
          }
        }

        // 2. Initialize AdMob ONLY after the ATT prompt has been answered (or skipped on Android)
        await MobileAds.instance.initialize();
      }

      await Supabase.initialize(
        url: 'https://rbpmgzcafsykjbljgfvl.supabase.co', 
        anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJicG1nemNhZnN5a2pibGpnZnZsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY5MzEzMTgsImV4cCI6MjEwMjUwNzMxOH0.z-Th0EOWSqr4M7UcDrZUNO4U_ylhJ_nVB0VcUPWAYHA',
      );

      if (!kIsWeb) {
        await Purchases.setLogLevel(LogLevel.debug);
        if (Platform.isIOS) {
          await Purchases.configure(PurchasesConfiguration("appl_aJcMjydRQhDoZUvQpUjQgNpLPyH")); 
        } else if (Platform.isAndroid) {
          await Purchases.configure(PurchasesConfiguration("goog_NvbOeRUARSAPSunHAVZSjcKjoWE"));
        }
      }

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

      // 4. Launch the app inside the same zone
      runApp(
        EasyLocalization(
          supportedLocales: const [
            Locale('en'), 
            Locale('es'), 
            Locale('pt', 'BR'), // Split regional codes
            Locale('ja'), 
            Locale('ko'), 
            Locale('de'), 
            Locale('fr'), 
            Locale('ru'), 
            Locale('hi'), 
            Locale('fa'), 
            Locale('ar')
          ],
          path: 'assets/translations', 
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
    
    // --- NEW: START LISTENING FOR INVITE LINKS IMMEDIATELY ---
    DeepLinkHandler.init();
    
    _lifecycleListener = AppLifecycleListener(
      onPause: () => AudioManager.instance.mute(),
      onInactive: () => AudioManager.instance.mute(),
      onResume: () => AudioManager.instance.unmute(),
    );
  }

  @override
  void dispose() {
    // --- NEW: CLEANUP LINK LISTENER ---
    DeepLinkHandler.dispose();
    
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // --- Safe Localization Fallback ---
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
      home: const AuthGatekeeper(), 
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

// ============================================================================
// THE GUEST PASS DEEP LINK CATCHER
// ============================================================================
class DeepLinkHandler {
  static late AppLinks _appLinks;
  static StreamSubscription<Uri>? _linkSubscription;

  static void init() {
    _appLinks = AppLinks();

    // Catch links while the app is actively running or in the background
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _processUri(uri);
    });
  }

  static Future<void> _processUri(Uri uri) async {
    // Look for our specific Fright Night web URL path
    if (uri.path.contains('/guest')) {
      final eventId = uri.queryParameters['event'];
      if (eventId != null) {
        final prefs = await SharedPreferences.getInstance();
        final supabase = Supabase.instance.client;
        
        if (supabase.auth.currentUser != null) {
          // Player is already logged in, grant the guest pass immediately
          try {
            await supabase.from('fright_night_rsvps').upsert({
              'event_id': eventId,
              'user_id': supabase.auth.currentUser!.id,
              'status': 'guest_pass',
            });
            debugPrint('Mercenary Guest Pass activated for event: $eventId');
          } catch (e) {
            debugPrint('Failed to apply guest pass: $e');
          }
        } else {
          // Brand new player! Save the ID so we can apply it after they register
          await prefs.setString('pending_guest_pass', eventId);
          debugPrint('Brand new player invite caught. Saving $eventId to cache.');
        }
      }
    }
  }

  static void dispose() {
    _linkSubscription?.cancel();
  }
}