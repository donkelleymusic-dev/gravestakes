import 'package:flame/components.dart';
import 'package:flame/events.dart'; 
import 'package:flame/text.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'game.dart';

class ExitButton extends PositionComponent with TapCallbacks, HasGameReference<GraveStakesGame> { 
  ExitButton() : super( 
    size: Vector2(40, 40), 
    position: Vector2(0, 75), 
    anchor: Anchor.topRight,  
  ); 

  @override
  void render(Canvas canvas) {
    final bgPaint = Paint()..color = Colors.black54;
    final borderPaint = Paint()..color = Colors.redAccent..style = PaintingStyle.stroke..strokeWidth = 2.5;
    final rect = RRect.fromRectAndRadius(size.toRect(), const Radius.circular(8));
    
    canvas.drawRRect(rect, bgPaint);
    canvas.drawRRect(rect, borderPaint);
    
    final textPainter = TextPaint(
      style: const TextStyle(
        color: Colors.redAccent, 
        fontSize: 26, 
        fontWeight: FontWeight.bold, 
        fontFamily: 'Orbitron'
      )
    );
    textPainter.render(canvas, 'X', Vector2(11, 4)); 
  }

  @override 
  void onTapDown(TapDownEvent event) { 
    final context = game.buildContext;
    if (context == null) return;

    // Pause the game engine while the dialog is open so they don't die while reading
    game.pauseEngine();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.black87,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Colors.redAccent, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Text(
            'FLEE THE CRYPT?', 
            style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, letterSpacing: 2, fontFamily: 'Orbitron'),
          ),
          content: const Text(
            'If you abandon the match now, you will forfeit your entry stake and abandon all loot gathered this round.\n\nAre you sure you want to flee?',
            style: TextStyle(color: Colors.white70, fontFamily: 'Orbitron'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Close dialog
                game.resumeEngine(); // Unpause game
              },
              child: const Text('STAY & FIGHT', style: TextStyle(color: Colors.grey, fontFamily: 'Orbitron')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800]),
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Close dialog
                game.resumeEngine(); // Unpause game to avoid memory leaks
                Navigator.of(context).pop(); // Pop the entire match screen
              },
              child: const Text('COWARD\'S ESCAPE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Orbitron')),
            ),
          ],
        );
      }
    );
  } 
}

class PlayerHud extends PositionComponent with HasGameReference<GraveStakesGame> {
  late TextComponent _profileText;
  late TextComponent _walletText;
  late TextComponent _matchStatsText;

  PlayerHud() : super(priority: 200);

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    // Halved the margin from 40 down to 20 to clear the bezel cleanly
    position = Vector2(size.x - 20, 40);
    anchor = Anchor.topRight;
    scale = Vector2.all(size.x < 600 ? 0.65 : 1.0);
  }

  @override
  Future<void> onLoad() async {
    final regularStyle = TextPaint(
      style: const TextStyle(color: Colors.white70, fontSize: 16, fontFamily: 'Orbitron'), 
    );
    final economyStyle = TextPaint(
      style: const TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Orbitron'),
    );
    final statsStyle = TextPaint(
      style: const TextStyle(color: Colors.cyanAccent, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Orbitron'),
    );

    _profileText = TextComponent(
      text: 'Syncing profile...', 
      textRenderer: regularStyle, 
      position: Vector2(0, 0),
      anchor: Anchor.topRight, 
    );
    
    // Hard-initialize to 0 for the start of the match
    _walletText = TextComponent(
      text: 'Shadows: 0', 
      textRenderer: economyStyle, 
      position: Vector2(0, 22), 
      anchor: Anchor.topRight, 
    );
    _matchStatsText = TextComponent(
      text: 'Coins: 0', 
      textRenderer: statsStyle, 
      position: Vector2(0, 44), 
      anchor: Anchor.topRight, 
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
    
    // Read the current session loot directly from the player's active state
    final shadows = player.score; 
    final coins = player.coinsEarned;
    
    final activeBuffs = <String>[];
    if (player.isInvisible) activeBuffs.add('Invis (${player.invisibilityTimer.toStringAsFixed(0)}s)');
    if (player.isDisguised) activeBuffs.add('Disguise (${player.disguiseTimer.toStringAsFixed(0)}s)');
    if (player.hasExtendedRange) activeBuffs.add('Range+');

    // FIXED: Prepend the buffs to the string so the "Coins: X" text stays locked to the right margin
    String buffStr = activeBuffs.isNotEmpty ? 'Buffs: ${activeBuffs.join(", ")} | ' : '';
    
    // Continually update the HUD with what they've collected *this* round
    _walletText.text = 'Shadows: $shadows';
    _matchStatsText.text = '${buffStr}Coins: $coins';
  }

  Future<void> fetchPlayerData() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    
    if (user == null) {
      _profileText.text = 'Guest Player';
      return;
    }

    try {
      // Stripped the wallet query out. We only pull the profile to get the level for your custom text format.
      final profile = await client.from('profiles').select('username, level').eq('id', user.id).single();

      final username = profile['username'] ?? 'Unknown Ghost';
      final level = profile['level'] ?? 1;

      // Restored your custom format
      _profileText.text = '$username LVL $level';
      
    } catch (e) {
      // Fallback if the network drops on map load
      _profileText.text = game.myUsername;
      debugPrint('Error fetching HUD profile: $e');
    }
  }
}