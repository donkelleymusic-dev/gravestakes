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
        fontSize: 20, // Reduced slightly from 24 to accommodate longer player names
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
    scale = Vector2.all(size.x < 600 ? 0.65 : 1.0);
  }

  @override
  void update(double dt) {
    super.update(dt);
    
    // Switch HUD display mode based on the current match format
    if (game.matchMode == '2v2') {
      int myTeamId = game.getEntityTeam(game.player);
      int myTeamScore = game.player.score;
      int enemyTeamScore = 0;
      
      List<String> myTeamNames = [game.myUsername]; // Use your actual name here too!
      List<String> enemyTeamNames = [];
      
      // 1. Gather Bot Scores & Names
      for (var bot in game.bots) {
        if (game.getEntityTeam(bot) == myTeamId) {
          myTeamScore += bot.simulatedScore;
          myTeamNames.add(bot.fakeUsername);
        } else {
          enemyTeamScore += bot.simulatedScore;
          enemyTeamNames.add(bot.fakeUsername);
        }
      }
      
      // 2. Gather Remote Player Scores & Names
      for (var entry in game.networkPlayers.entries) {
        String remoteName = entry.value.username; // <-- Read the real name!
        
        if (game.getEntityTeam(entry.key) == myTeamId) {
          myTeamScore += entry.value.score;
          myTeamNames.add(remoteName);
        } else {
          enemyTeamScore += entry.value.score;
          enemyTeamNames.add(remoteName);
        }
      }
      
      String myTeamStr = myTeamNames.join(' & ');
      String enemyTeamStr = enemyTeamNames.join(' & ');
      
      // Stack the 2v2 names vertically so they cleanly fit on portrait screens
      text = '[$myTeamStr]: $myTeamScore\n[$enemyTeamStr]: $enemyTeamScore';
      
    } else if (game.matchMode == '1on1' || game.matchMode == '1v1') {
      int myScore = game.player.score;
      int opponentScore = 0;
      String opponentName = 'OPPONENT';
      
      // Identify who the single opponent is
      for (var bot in game.bots) {
        opponentScore += bot.simulatedScore;
        opponentName = bot.fakeUsername;
      }
      for (var entry in game.networkPlayers.entries) {
        opponentScore += entry.value.score;
        opponentName = entry.value.username; // <-- Read the real name!
      }
      
      text = '${game.myUsername}: $myScore  |  $opponentName: $opponentScore';
      
    } else {
      text = 'SOULS: ${game.player.score}';
    }
  }
}