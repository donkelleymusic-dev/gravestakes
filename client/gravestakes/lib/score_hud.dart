import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'game.dart';

class ScoreHud extends TextComponent with HasGameReference<GraveStakesGame> {
  ScoreHud() : super(
    position: Vector2(20, 20),
    anchor: Anchor.topRight,
    priority: 100, 
  );

  @override
  Future<void> onLoad() async {
    textRenderer = TextPaint(
      style: const TextStyle(
        color: Colors.white,
        fontSize: 24,
        fontWeight: FontWeight.bold,
        shadows: [Shadow(color: Colors.red, blurRadius: 4)],
      ),
    );
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    position = Vector2(10, 40); 
    anchor = Anchor.topLeft;
  }

  @override
  void update(double dt) {
    super.update(dt);
    
    // Switch HUD display mode based on the current match format
    if (game.matchMode == '2v2') {
      int myTeamId = game.getEntityTeam(game.player);
      int myTeamScore = game.player.score;
      int enemyTeamScore = 0;
      
      for (var bot in game.bots) {
        if (game.getEntityTeam(bot) == myTeamId) myTeamScore += bot.simulatedScore;
        else enemyTeamScore += bot.simulatedScore;
      }
      for (var entry in game.networkPlayers.entries) {
        if (game.getEntityTeam(entry.key) == myTeamId) myTeamScore += entry.value.score;
        else enemyTeamScore += entry.value.score;
      }
      
      text = 'TEAM: $myTeamScore | ENEMY: $enemyTeamScore | YOU: ${game.player.score}';
    } else {
      text = 'SOULS COLLECTED: ${game.player.score}';
    }
  }
}