import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'game.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    // FIXED: Removed /rest/v1/ from the URL
    url: 'https://rbpmgzcafsykjbljgfvl.supabase.co', 
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJicG1nemNhZnN5a2pibGpnZnZsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY5MzEzMTgsImV4cCI6MjEwMjUwNzMxOH0.z-Th0EOWSqr4M7UcDrZUNO4U_ylhJ_nVB0VcUPWAYHA',
  );

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: GameWidget(game: GraveStakesGame()),
      ),
    ),
  );
}