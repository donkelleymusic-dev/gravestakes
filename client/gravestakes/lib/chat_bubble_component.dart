import 'package:flame/components.dart';
import 'package:flutter/material.dart';

class ChatBubbleComponent extends PositionComponent {
  final String text;
  final Color borderColor;
  late TextComponent _textComponent;
  
  double _lifeTimer = 2.5;

  ChatBubbleComponent({
    required this.text,
    this.borderColor = Colors.cyanAccent,
  }) : super(anchor: Anchor.bottomCenter);

  @override
  Future<void> onLoad() async {
    final textPaint = TextPaint(
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontFamily: 'Courier',
        fontWeight: FontWeight.bold,
      ),
    );

    _textComponent = TextComponent(
      text: text,
      textRenderer: textPaint,
      anchor: Anchor.center,
    );

    // Auto-size the bubble with padding
    size = Vector2(_textComponent.size.x + 16, _textComponent.size.y + 12);
    _textComponent.position = size / 2;
    
    add(_textComponent);
    
    // Spawn directly above the player's collision box
    position = Vector2(0, -40);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _lifeTimer -= dt;
    
    // Smoothly float upward
    position.y -= 15 * dt;

    if (_lifeTimer <= 0) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    // Calculate a smooth fade-out during the last 0.5 seconds
    final opacity = (_lifeTimer / 0.5).clamp(0.0, 1.0);
    
    final bgPaint = Paint()..color = Colors.black87.withOpacity(opacity * 0.87);
    final borderPaint = Paint()
      ..color = borderColor.withOpacity(opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final rrect = RRect.fromRectAndRadius(
      size.toRect(),
      const Radius.circular(6),
    );

    canvas.drawRRect(rrect, bgPaint);
    canvas.drawRRect(rrect, borderPaint);
    
    super.render(canvas); 
  }
}