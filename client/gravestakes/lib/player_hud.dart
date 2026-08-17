import 'package:flame/components.dart';
import 'package:flame/events.dart'; // <-- Required for TapCallbacks!
import 'package:flame/text.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'game.dart';

// 1. Create a custom tappable component
class ExitButton extends TextComponent with TapCallbacks, HasGameReference<GraveStakesGame> {
  ExitButton() : super(
    text: '[ EXIT MATCH ]',
    textRenderer: TextPaint(style: const TextStyle(color: Colors.grey, fontSize: 14)),
    position: Vector2(0, 50),
  );

  @override
  void onTapDown(TapDownEvent event) {
    // This pops the Flame Game engine off the screen and returns to the Main Menu!
    if (game.buildContext != null) {
      Navigator.of(game.buildContext!).pop();
    }
  }
}

class PlayerHud extends PositionComponent with HasGameReference<GraveStakesGame> {
  late TextComponent _profileText;
  late TextComponent _walletText;

  PlayerHud() : super(position: Vector2(20, 20), priority: 200);

  @override
  Future<void> onLoad() async {
    final regularStyle = TextPaint(
      style: const TextStyle(color: Colors.white70, fontSize: 16, fontFamily: 'Courier'),
    );
    final economyStyle = TextPaint(
      style: const TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Courier'),
    );

    _profileText = TextComponent(text: 'Syncing profile...', textRenderer: regularStyle);
    _walletText = TextComponent(
      text: 'Shadows: -- | Stakes: --', 
      textRenderer: economyStyle, 
      position: Vector2(0, 25), 
    );

    add(_profileText);
    add(_walletText);
    
    // 2. Add our new tappable button instead of the basic TextComponent
    add(ExitButton());

    await fetchPlayerData();
  }

  Future<void> fetchPlayerData() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    
    if (user == null) {
      _profileText.text = 'Guest Player';
      return;
    }

    try {
      final responses = await Future.wait([
        client.from('profiles').select('username, level').eq('id', user.id).single(),
        client.from('wallets').select('shadows, stakes').eq('id', user.id).single(),
      ]);

      final profile = responses[0];
      final wallet = responses[1];

      final username = profile['username'] ?? 'Unknown Ghost';
      final level = profile['level'] ?? 1;
      final shadows = wallet['shadows'] ?? 0;
      final stakes = wallet['stakes'] ?? 0;

      _profileText.text = '$username (Lv. $level)';
      _walletText.text = 'Shadows: $shadows | Stakes: $stakes';
      
    } catch (e) {
      _profileText.text = 'Database Sync Failed';
      _walletText.text = '';
      debugPrint('Error fetching HUD data: $e');
    }
  }
}