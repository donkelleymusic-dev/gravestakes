import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'game.dart';
import 'chat_bubble_component.dart';

class QuickChatWheel extends PositionComponent with DragCallbacks, HasGameReference<GraveStakesGame> {
  bool _isActive = false;
  Vector2 _dragDelta = Vector2.zero();
  
  double _cooldownTimer = 0.0;
  final double _maxCooldown = 3.0;

  // Update this line to include the priority
  QuickChatWheel() : super(size: Vector2.all(60), anchor: Anchor.center, priority: 200000);

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    position = Vector2(100, size.y - 240);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_cooldownTimer > 0) {
      _cooldownTimer -= dt;
    }
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (_cooldownTimer > 0) return; 
    
    _isActive = true;
    _dragDelta = Vector2.zero();
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (_isActive) {
      _dragDelta += event.localDelta;
    }
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (_isActive && _dragDelta.length > 20) {
      _executePing();
    }
    _isActive = false;
    _dragDelta = Vector2.zero();
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    _isActive = false;
  }

  // --- DYNAMIC LOADOUT HELPERS ---
  bool get _isDuel => game.matchMode == '1v1';

  String get _msgUp => _isDuel ? 'RUN.' : 'SWARMED!';
  String get _msgRight => _isDuel ? 'NICE TRY.' : 'PUSHING!';
  String get _msgDown => _isDuel ? 'BEHIND YOU.' : 'REGROUP!';
  String get _msgLeft => 'GOTCHA.';

  void _executePing() {
    _cooldownTimer = _maxCooldown; 
    
    final angle = _dragDelta.screenAngle();
    String message;
    Color color;

    if (angle >= -pi/4 && angle < pi/4) {
      message = _msgUp;
      color = Colors.redAccent;
    } else if (angle >= pi/4 && angle < 3*pi/4) {
      message = _msgRight;
      color = Colors.orangeAccent;
    } else if (angle >= 3*pi/4 || angle < -3*pi/4) {
      message = _msgDown;
      color = Colors.cyanAccent;
    } else {
      message = _msgLeft;
      color = Colors.purpleAccent;
    }

    game.player.add(ChatBubbleComponent(text: message, borderColor: color));

    game.myChannel.sendBroadcastMessage(
      event: 'quick_chat', 
      payload: {
        'id': game.mySessionId,
        'text': message,
        'color': color.value,
      }
    );
  }

  @override
  void render(Canvas canvas) {
    final baseOpacity = _cooldownTimer > 0 ? 0.05 : 0.2;
    final basePaint = Paint()..color = Colors.white.withOpacity(baseOpacity);
    canvas.drawCircle(Offset(size.x / 2, size.y / 2), size.x / 2, basePaint);

    if (_cooldownTimer > 0) {
      final progress = 1.0 - (_cooldownTimer / _maxCooldown);
      final arcPaint = Paint()
        ..color = Colors.cyanAccent.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
        
      canvas.drawArc(
        Rect.fromCircle(center: Offset(size.x / 2, size.y / 2), radius: size.x / 2),
        -pi / 2, 
        progress * 2 * pi, 
        false,
        arcPaint,
      );
    }

    if (_isActive) {
      final center = Offset(size.x / 2, size.y / 2);
      
      // Pass the dynamic text strings to the renderer
      _drawSlice(canvas, center, _msgUp, Colors.redAccent, 0);
      _drawSlice(canvas, center, _msgRight, Colors.orangeAccent, pi/2);
      _drawSlice(canvas, center, _msgDown, Colors.cyanAccent, pi);
      _drawSlice(canvas, center, _msgLeft, Colors.purpleAccent, -pi/2);

      Vector2 boundedDelta = _dragDelta.clone();
      if (boundedDelta.length > 60.0) {
        boundedDelta.normalize();
        boundedDelta.scale(60.0);
      }
      
      final thumbPaint = Paint()..color = Colors.white;
      canvas.drawCircle(center + Offset(boundedDelta.x, boundedDelta.y), 10, thumbPaint);
    }
  }

  void _drawSlice(Canvas canvas, Offset center, String text, Color color, double angle) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
      textDirection: TextDirection.ltr,
    )..layout();
    
    final dx = sin(angle) * 70;
    final dy = -cos(angle) * 70;
    
    textPainter.paint(canvas, center + Offset(dx - (textPainter.width / 2), dy - (textPainter.height / 2)));
  }
}