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
  
  // The threshold between the inner (Category) ring and outer (Specific) ring
  final double _tierThreshold = 45.0; 

  QuickChatWheel() : super(size: Vector2.all(80), anchor: Anchor.center, priority: 200000);

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    position = Vector2(110, size.y - 240);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_cooldownTimer > 0) _cooldownTimer -= dt;
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
    if (_isActive) _dragDelta += event.localDelta;
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    // Only execute if they committed by dragging into the outer tier
    if (_isActive && _dragDelta.length > _tierThreshold) {
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

  // --- DYNAMIC DICTIONARIES ---
  String _getQuadrant(double angle) {
    if (angle >= -pi/4 && angle < pi/4) return 'UP';
    if (angle >= pi/4 && angle < 3*pi/4) return 'RIGHT';
    if (angle >= 3*pi/4 || angle < -3*pi/4) return 'DOWN';
    return 'LEFT';
  }

  Map<String, Map<String, String>> get _loadout {
    bool isDuel = game.matchMode == '1v1';
    bool isSquad = game.isGunner || game.hasGunner || game.matchMode == '2v2';

    return {
      'UP': { // STATUS (Red)
        'LABEL': 'STATUS',
        'UP': 'SWARMED!',
        'RIGHT': 'NO STAMINA!',
        'DOWN': 'DEAD LIGHT!',
        'LEFT': 'STUNNED!',
      },
      'RIGHT': { // COMBAT (Orange)
        'LABEL': 'COMBAT',
        'UP': 'PUSHING!',
        'RIGHT': 'NEED STUN!',
        'DOWN': 'FALL BACK!',
        'LEFT': 'MASK DOWN!',
      },
      'DOWN': { // TACTICAL (Cyan)
        'LABEL': 'TACTIC',
        'UP': 'REGROUP!',
        'RIGHT': 'HOLD HERE.',
        'DOWN': 'LOOT HERE!',
        'LEFT': 'FLANKING!',
      },
      'LEFT': { // SOCIAL / SQUAD (Purple)
        'LABEL': isSquad ? 'SQUAD' : (isDuel ? 'TAUNT' : 'SOCIAL'),
        'UP': isSquad ? 'TEAM: FOCUS HERE!' : (isDuel ? 'RUN.' : 'HELP!'),
        'RIGHT': isSquad ? 'TEAM: BATTERY DEAD!' : (isDuel ? 'NICE TRY.' : 'TRUCE?'),
        'DOWN': isSquad ? 'TEAM: RETREAT!' : (isDuel ? 'BEHIND YOU.' : 'SORRY!'),
        'LEFT': isSquad ? 'TEAM: NEED ENERGY!' : (isDuel ? 'GOTCHA.' : 'GOTCHA.'),
      }
    };
  }

  void _executePing() {
    _cooldownTimer = _maxCooldown; 
    
    String categoryQuad = _getQuadrant(_dragDelta.screenAngle());
    String specificQuad = _getQuadrant(_dragDelta.screenAngle()); 
    
    Color color = Colors.white;
    if (categoryQuad == 'UP') color = Colors.redAccent;
    if (categoryQuad == 'RIGHT') color = Colors.orangeAccent;
    if (categoryQuad == 'DOWN') color = Colors.cyanAccent;
    if (categoryQuad == 'LEFT') color = Colors.purpleAccent;

    String message = _loadout[categoryQuad]![specificQuad]!;
    bool isPrivate = message.startsWith('TEAM:');

    game.player.add(ChatBubbleComponent(text: message, borderColor: color));

    game.myChannel.sendBroadcastMessage(
      event: 'quick_chat', 
      payload: {
        'id': game.mySessionId,
        'text': message,
        'color': color.value,
        'target_id': isPrivate ? 'squad' : 'all',
      }
    );
  }

  @override
  void render(Canvas canvas) {
    final center = Offset(size.x / 2, size.y / 2);

    final baseOpacity = _cooldownTimer > 0 ? 0.05 : 0.2;
    canvas.drawCircle(center, _tierThreshold, Paint()..color = Colors.black.withOpacity(baseOpacity));
    canvas.drawCircle(center, _tierThreshold, Paint()..color = Colors.white.withOpacity(baseOpacity)..style = PaintingStyle.stroke);

    // Resting Cooldown Ring
    if (_cooldownTimer > 0) {
      final progress = 1.0 - (_cooldownTimer / _maxCooldown);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: _tierThreshold),
        -pi / 2, progress * 2 * pi, false,
        Paint()..color = Colors.cyanAccent.withOpacity(0.6)..style = PaintingStyle.stroke..strokeWidth = 2.0,
      );
    }

    if (_isActive) {
      String currentCategory = _getQuadrant(_dragDelta.screenAngle());
      bool isOuterRing = _dragDelta.length > _tierThreshold;

      // Draw the Outer Ring Background dynamically
      canvas.drawCircle(center, 90.0, Paint()..color = Colors.black87.withOpacity(0.8));
      canvas.drawCircle(center, 90.0, Paint()..color = Colors.cyanAccent.withOpacity(0.3)..style = PaintingStyle.stroke);

      if (!isOuterRing) {
        // TIER 1: Showing Categories
        _drawText(canvas, center, _loadout['UP']!['LABEL']!, Colors.redAccent, 0, 30);
        _drawText(canvas, center, _loadout['RIGHT']!['LABEL']!, Colors.orangeAccent, pi/2, 30);
        _drawText(canvas, center, _loadout['DOWN']!['LABEL']!, Colors.cyanAccent, pi, 30);
        _drawText(canvas, center, _loadout['LEFT']!['LABEL']!, Colors.purpleAccent, -pi/2, 30);
      } else {
        // TIER 2: Pushed into the outer ring, showing specific shouts for the selected category
        Map<String, String> activeSet = _loadout[currentCategory]!;
        Color activeColor = currentCategory == 'UP' ? Colors.redAccent : 
                           (currentCategory == 'RIGHT' ? Colors.orangeAccent : 
                           (currentCategory == 'DOWN' ? Colors.cyanAccent : Colors.purpleAccent));

        // Center Label (Faded)
        _drawText(canvas, center, activeSet['LABEL']!, activeColor.withOpacity(0.5), 0, 0);

        // Subcategory Targets
        _drawText(canvas, center, activeSet['UP']!, activeColor, 0, 65);
        _drawText(canvas, center, activeSet['RIGHT']!, activeColor, pi/2, 65);
        _drawText(canvas, center, activeSet['DOWN']!, activeColor, pi, 65);
        _drawText(canvas, center, activeSet['LEFT']!, activeColor, -pi/2, 65);
      }

      // Draw the Thumb Drag Indicator
      Vector2 boundedDelta = _dragDelta.clone();
      if (boundedDelta.length > 90.0) {
        boundedDelta.normalize();
        boundedDelta.scale(90.0);
      }
      canvas.drawCircle(center + Offset(boundedDelta.x, boundedDelta.y), 12, Paint()..color = Colors.white);
    }
  }

  void _drawText(Canvas canvas, Offset center, String text, Color color, double angle, double distance) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
      textDirection: TextDirection.ltr,
    )..layout();
    
    final dx = sin(angle) * distance;
    final dy = -cos(angle) * distance;
    textPainter.paint(canvas, center + Offset(dx - (textPainter.width / 2), dy - (textPainter.height / 2)));
  }
}