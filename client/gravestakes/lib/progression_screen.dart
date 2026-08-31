import 'package:flutter/material.dart';

class ProgressionScreen extends StatelessWidget {
  final int oldXp;
  final int newXp;
  final int xpRequired;
  final int shadowsEarned;
  final int coinsEarned;

  const ProgressionScreen({
    super.key, 
    required this.oldXp, 
    required this.newXp, 
    required this.xpRequired, 
    required this.shadowsEarned, 
    required this.coinsEarned
  });

  @override
  Widget build(BuildContext context) {
    double safeXpRequired = xpRequired > 0 ? xpRequired.toDouble() : 1.0;
    
    // Fill ratios based on actual level progress
    double oldFill = oldXp / safeXpRequired;
    double newFill = newXp / safeXpRequired;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('ACCOUNT RESONANCE', style: TextStyle(color: Colors.cyanAccent, fontSize: 28, letterSpacing: 4, fontFamily: 'Courier')),
            const SizedBox(height: 10),
            Text('XP EARNED THIS MATCH: +${newXp - oldXp}', style: const TextStyle(color: Colors.white70, fontSize: 14, fontFamily: 'Courier')),
            const SizedBox(height: 30),
            
            // The Resonance Chamber (XP Bar)
            SizedBox(
              height: 250,
              width: 60,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  // Empty Glass Vial
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white30, width: 2),
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30), top: Radius.circular(5)),
                      color: Colors.black54,
                    ),
                  ),
                  // Animated Liquid Fill using REAL XP progress
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: oldFill, end: newFill),
                    duration: const Duration(milliseconds: 2200),
                    curve: Curves.easeOutCubic,
                    builder: (context, fillRatio, child) {
                      return FractionallySizedBox(
                        heightFactor: fillRatio.clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter, end: Alignment.topCenter,
                              colors: [Colors.cyan[900]!, Colors.cyanAccent],
                            ),
                            boxShadow: [BoxShadow(color: Colors.cyanAccent.withOpacity(0.5), blurRadius: 15)],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 40),
            
            // Ticking Stat Counters for Real Earned Values
            SizedBox(
              width: 260,
              child: Column(
                children: [
                  AnimatedStatTicker(label: 'SHADOWS EXTRACTED', beginVal: 0, endVal: shadowsEarned, color: Colors.redAccent),
                  const SizedBox(height: 12),
                  AnimatedStatTicker(label: 'COINS SALVAGED', beginVal: 0, endVal: coinsEarned, color: Colors.yellowAccent),
                  const SizedBox(height: 12),
                  AnimatedStatTicker(label: 'CURRENT XP', beginVal: oldXp, endVal: newXp, color: Colors.cyanAccent),
                ],
              ),
            ),

            const SizedBox(height: 50),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[900], side: const BorderSide(color: Colors.white)),
              onPressed: () {
                // Returns the player cleanly back to the Main Menu
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: const Text('RETURN TO BASE', style: TextStyle(color: Colors.white, fontFamily: 'Courier')),
            )
          ],
        ),
      ),
    );
  }
}

class AnimatedStatTicker extends StatefulWidget {
  final String label;
  final int beginVal;
  final int endVal;
  final Color color;

  const AnimatedStatTicker({super.key, required this.label, required this.beginVal, required this.endVal, required this.color});

  @override
  State<AnimatedStatTicker> createState() => _AnimatedStatTickerState();
}

class _AnimatedStatTickerState extends State<AnimatedStatTicker> {
  int lastTicked = 0;

  @override
  void initState() {
    super.initState();
    lastTicked = widget.beginVal;
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: widget.beginVal.toDouble(), end: widget.endVal.toDouble()),
      duration: const Duration(milliseconds: 2000),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        int currentVal = value.toInt();

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(widget.label, style: const TextStyle(color: Colors.white70, fontFamily: 'Courier', fontSize: 12)),
            Text(
              '$currentVal',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Courier',
                color: widget.color,
                shadows: [Shadow(color: widget.color, blurRadius: 8)],
              ),
            ),
          ],
        );
      },
    );
  }
}