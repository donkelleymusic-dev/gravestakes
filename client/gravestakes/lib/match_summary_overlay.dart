import 'package:flutter/material.dart';
import 'game.dart';
import 'vessel_opener_overlay.dart';

class MatchSummaryOverlay extends StatelessWidget {
  final GraveStakesGame game;

  const MatchSummaryOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    bool isTeamMode = game.matchMode == '2v2';
    int myTeamId = game.getEntityTeam(game.player);

    // 1. Gather individual scores and team assignments
    List<Map<String, dynamic>> playerResults = [
      {'name': 'YOU', 'score': game.player.score, 'isMe': true, 'team': myTeamId}
    ];

    int myTeamScore = game.player.score;
    int enemyTeamScore = 0;

    game.networkPlayers.forEach((id, remote) {
      final shortId = id.length >= 4 ? id.substring(0, 4) : id;
      int remoteTeam = game.getEntityTeam(id);
      
      playerResults.add({'name': 'Player $shortId', 'score': remote.score, 'isMe': false, 'team': remoteTeam});

      if (isTeamMode) {
        if (remoteTeam == myTeamId) {
          myTeamScore += remote.score;
        } else {
          enemyTeamScore += remote.score;
        }
      }
    });

    // Add bot scores to the team totals if playing 2v2
    if (isTeamMode) {
      for (var bot in game.bots) {
        if (game.getEntityTeam(bot) == myTeamId) {
          myTeamScore += bot.simulatedScore;
        } else {
          enemyTeamScore += bot.simulatedScore;
        }
      }
    }

    // Sort individuals highest to lowest
    playerResults.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

    // Determine Victory or Defeat
    String matchResultText = 'MATCH RESULTS';
    Color resultColor = Colors.white;
    
    if (isTeamMode) {
      if (myTeamScore > enemyTeamScore) {
        matchResultText = 'VICTORY!';
        resultColor = Colors.greenAccent;
      } else if (myTeamScore < enemyTeamScore) {
        matchResultText = 'DEFEAT';
        resultColor = Colors.redAccent;
      } else {
        matchResultText = 'DRAW';
        resultColor = Colors.yellowAccent;
      }
    } else {
      // 1v1 or Casual logic
      if (playerResults.isNotEmpty && playerResults.first['isMe'] == true) {
        matchResultText = 'VICTORY!';
        resultColor = Colors.greenAccent;
      } else {
        matchResultText = 'DEFEAT';
        resultColor = Colors.redAccent;
      }
    }

    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          width: 350,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.95),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: resultColor, width: 2),
            boxShadow: [BoxShadow(color: resultColor.withOpacity(0.2), blurRadius: 20)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                matchResultText, 
                style: TextStyle(color: resultColor, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 2, fontFamily: 'Courier', shadows: [Shadow(color: resultColor, blurRadius: 8)]),
              ),
              
              if (isTeamMode) ...[
                 const SizedBox(height: 16),
                 Text('YOUR SQUAD: $myTeamScore', style: const TextStyle(color: Colors.cyanAccent, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
                 Text('ENEMY SQUAD: $enemyTeamScore', style: const TextStyle(color: Colors.orangeAccent, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
              ],
              
              const SizedBox(height: 24),
              const Divider(color: Colors.white24),
              const SizedBox(height: 8),
              
              ...playerResults.map((p) {
                Color rowColor = p['isMe'] ? Colors.cyanAccent : Colors.white;
                
                // Color-code teammates vs enemies in 2v2
                if (isTeamMode && !p['isMe']) {
                  rowColor = (p['team'] == myTeamId) ? Colors.cyanAccent.withOpacity(0.7) : Colors.orangeAccent.withOpacity(0.7);
                }
                
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(p['name'], style: TextStyle(color: rowColor, fontSize: 18, fontWeight: p['isMe'] ? FontWeight.bold : FontWeight.normal, fontFamily: 'Courier')),
                      Text('${p['score']}', style: TextStyle(color: rowColor, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
                    ],
                  ),
                );
              }),
              
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purpleAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                ),
                onPressed: () {
                  // 1. Hide the competitive scoreboard
                  game.overlays.remove('summary');
                  
                  // 2. Launch the personal rewards phase
                  VesselOpenerOverlay.show(context, 'soul_casket');
                },
                child: const Text('CLAIM REWARDS', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}