import 'package:flutter/material.dart';
import 'game.dart';

class MatchSummaryOverlay extends StatelessWidget {
  final GraveStakesGame game;

  const MatchSummaryOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> scores = [
      {'name': 'YOU', 'score': game.player.score, 'isMe': true}
    ];
    
    game.networkPlayers.forEach((id, remote) {
      // FIX: Prevent substring crash if testing with short string IDs
      final shortId = id.length >= 4 ? id.substring(0, 4) : id;
      scores.add({'name': 'Player $shortId', 'score': remote.score, 'isMe': false});
    });

    scores.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

    // FIX: Wrapping the overlay in a Material widget stops the grey screen crash!
    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          width: 350,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.95),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.redAccent, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('MATCH RESULTS', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2)),
              const SizedBox(height: 24),
              
              ...scores.map((s) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(s['name'], style: TextStyle(color: s['isMe'] ? Colors.redAccent : Colors.white, fontSize: 18, fontWeight: s['isMe'] ? FontWeight.bold : FontWeight.normal)),
                    Text('${s['score']}', style: TextStyle(color: s['isMe'] ? Colors.redAccent : Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              )),
              
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                ),
                onPressed: () {
                  game.resetForNextRound();
                },
                child: const Text('CONTINUE', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}