import 'dart:math';
import 'package:flutter/material.dart';

class FlyingCurrencyOverlay {
  static void fly({
    required BuildContext context,
    required Offset start,
    required Offset end,
    required IconData icon,
    required Color color,
    int particleCount = 6,
    VoidCallback? onComplete,
  }) {
    final overlayState = Overlay.of(context);
    final random = Random();

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _ParticleFlightAnimation(
        start: start,
        end: end,
        icon: icon,
        color: color,
        count: particleCount,
        random: random,
        onFinished: () {
          entry.remove();
          onComplete?.call();
        },
      ),
    );

    overlayState.insert(entry);
  }
}

class _ParticleFlightAnimation extends StatefulWidget {
  final Offset start;
  final Offset end;
  final IconData icon;
  final Color color;
  final int count;
  final Random random;
  final VoidCallback onFinished;

  const _ParticleFlightAnimation({
    required this.start,
    required this.end,
    required this.icon,
    required this.color,
    required this.count,
    required this.random,
    required this.onFinished,
  });

  @override
  State<_ParticleFlightAnimation> createState() => _ParticleFlightAnimationState();
}

class _ParticleFlightAnimationState extends State<_ParticleFlightAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<double> _curveOffsets;

  @override
  void initState() {
    super.initState();
    _curveOffsets = List.generate(widget.count, (_) => (widget.random.nextDouble() - 0.5) * 160.0);
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
    _controller.forward().then((_) => widget.onFinished());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = Curves.easeInOutCubic.transform(_controller.value);
          return Stack(
            children: List.generate(widget.count, (i) {
              // Stagger particle arrival times
              final delay = i * (0.3 / widget.count);
              final particleT = ((t - delay) / (1.0 - delay)).clamp(0.0, 1.0);
              if (particleT <= 0.0) return const SizedBox.shrink();

              // Quadratic Bezier arc with lateral scatter
              final currentX = (1 - particleT) * widget.start.dx + particleT * widget.end.dx + sin(particleT * pi) * _curveOffsets[i];
              final currentY = (1 - particleT) * widget.start.dy + particleT * widget.end.dy;

              final scale = (sin(particleT * pi) * 0.5) + 0.8;
              final opacity = (1.0 - particleT * 0.3).clamp(0.0, 1.0);

              return Positioned(
                left: currentX - 12,
                top: currentY - 12,
                child: Opacity(
                  opacity: opacity,
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: widget.color.withOpacity(0.6), blurRadius: 10, spreadRadius: 2),
                        ],
                      ),
                      child: Icon(widget.icon, color: widget.color, size: 22),
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}