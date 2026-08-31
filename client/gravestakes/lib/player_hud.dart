import 'package:flame/components.dart';
import 'package:flame/events.dart'; 
import 'package:flame/text.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'game.dart';

class ExitButton extends TextComponent with TapCallbacks, HasGameReference<GraveStakesGame> { 
  ExitButton() : super( 
    text: '[ EXIT MATCH ]', 
    textRenderer: TextPaint(style: const TextStyle(color: Colors.grey, fontSize: 14)), 
    position: Vector2(0, 72), // Moved down to clear space!
    anchor: Anchor.topRight,  // <-- Align to the right edge
  ); 

  @override 
  void onTapDown(TapDownEvent event) { 
    if (game.buildContext != null) { 
      Navigator.of(game.buildContext!).pop(); 
    } 
  } 
}

class PlayerHud extends PositionComponent with HasGameReference<GraveStakesGame> {
  late TextComponent _profileText;
  late TextComponent _walletText;
  late TextComponent _matchStatsText;

  int _cachedShadows = 0;

  PlayerHud() : super(priority: 200);

  // ==========================================
  // NEW: Dynamic Resizing for Portrait Screens!
  // ==========================================
  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    position = Vector2(size.x - 10, 40); // Tighter to the edge
    anchor = Anchor.topRight;
    scale = Vector2.all(size.x < 600 ? 0.65 : 1.0);
  }

  @override
  Future<void> onLoad() async {
    final regularStyle = TextPaint(
      style: const TextStyle(color: Colors.white70, fontSize: 14, fontFamily: 'Courier'), // Slightly smaller font for mobile
    );
    final economyStyle = TextPaint(
      style: const TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Courier'),
    );
    final statsStyle = TextPaint(
      style: const TextStyle(color: Colors.cyanAccent, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Courier'),
    );

    _profileText = TextComponent(
      text: 'Syncing profile...', 
      textRenderer: regularStyle, 
      position: Vector2(0, 0),
      anchor: Anchor.topRight, // <-- Align to the right edge
    );
    _walletText = TextComponent(
      text: 'Shadows: --', 
      textRenderer: economyStyle, 
      position: Vector2(0, 22), 
      anchor: Anchor.topRight, // <-- Align to the right edge
    );
    _matchStatsText = TextComponent(
      text: '', 
      textRenderer: statsStyle, 
      position: Vector2(0, 44), 
      anchor: Anchor.topRight, // <-- Align to the right edge
    );

    add(_profileText);
    add(_walletText);
    add(_matchStatsText);
    add(ExitButton());

    await fetchPlayerData();
  }

  @override
  void update(double dt) {
    super.update(dt);
    
    final player = game.player;
    final coins = player.coinsEarned;
    
    final activeBuffs = <String>[];
    if (player.isInvisible) activeBuffs.add('Invis (${player.invisibilityTimer.toStringAsFixed(0)}s)');
    if (player.isDisguised) activeBuffs.add('Bush (${player.disguiseTimer.toStringAsFixed(0)}s)');
    if (player.hasExtendedRange) activeBuffs.add('Range+');

    String buffStr = activeBuffs.isNotEmpty ? ' | Buffs: ${activeBuffs.join(", ")}' : '';
    _matchStatsText.text = 'Coins: $coins$buffStr';
  }

  Future<void> fetchPlayerData() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    
    if (user == null) {
      _profileText.text = 'Guest Player';
      _walletText.text = 'Shadows: 0';
      return;
    }

    try {
      final responses = await Future.wait([
        client.from('profiles').select('username, level').eq('id', user.id).single(),
        client.from('wallets').select('shadows').eq('id', user.id).single(),
      ]);

      final profile = responses[0];
      final wallet = responses[1];

      final username = profile['username'] ?? 'Unknown Ghost';
      final level = profile['level'] ?? 1;
      _cachedShadows = wallet['shadows'] ?? 0;

      _profileText.text = '$username (Lv. $level)';
      _walletText.text = 'Shadows: $_cachedShadows';
      
    } catch (e) {
      _profileText.text = 'Database Sync Failed';
      _walletText.text = 'Shadows: 0';
      debugPrint('Error fetching HUD data: $e');
    }
  }
}