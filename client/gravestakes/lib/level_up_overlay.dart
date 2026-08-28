import 'package:flutter/material.dart';
import 'dart:math' as math;

class LevelUpOverlay extends StatefulWidget {
  final int newLevel;
  const LevelUpOverlay({super.key, required this.newLevel});

  static void show(BuildContext context, int newLevel) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => LevelUpOverlay(newLevel: newLevel),
    );
  }

  @override
  State<LevelUpOverlay> createState() => _LevelUpOverlayState();
}

class _LevelUpOverlayState extends State<LevelUpOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.92),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.amberAccent, width: 2),
            boxShadow: [
              BoxShadow(color: Colors.amberAccent.withOpacity(0.4), blurRadius: 25, spreadRadius: 5),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'RANK UP!',
                style: TextStyle(
                  color: Colors.amberAccent,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  fontFamily: 'Courier',
                ),
              ),
              const SizedBox(height: 24),
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Transform(
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.003) // Perspective depth
                      ..rotateY(_controller.value * 2 * math.pi),
                    alignment: Alignment.center,
                    child: Container(
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [Colors.amber, Colors.deepOrange.shade900],
                        ),
                        boxShadow: [
                          BoxShadow(color: Colors.amber.withOpacity(0.6), blurRadius: 15, spreadRadius: 2),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          'LV ${widget.newLevel}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Courier',
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              Text(
                'You have attained Level ${widget.newLevel}!\nYour acoustic power grows.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14, fontFamily: 'Courier'),
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber[800],
                  padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'AWESOME!', 
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontFamily: 'Courier'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}