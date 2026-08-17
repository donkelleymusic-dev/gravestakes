import 'package:flame/components.dart';
import 'package:flutter/material.dart';

class RemotePlayer extends PositionComponent {
  String currentColorStr = 'red';
  late RectangleComponent _sprite;

  RemotePlayer() : super(size: Vector2.all(32.0), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    _sprite = RectangleComponent(
      size: size, 
      paint: Paint()..color = Colors.redAccent,
    );
    add(_sprite);
  }

  // Updated to accept the optional color string
  void updatePosition(double newX, double newY, double newAngle, {String? colorStr}) {
    position.x = newX;
    position.y = newY;
    angle = newAngle;

    // If the network gave us a color we aren't currently using, switch to it!
    if (colorStr != null && colorStr != currentColorStr) {
      currentColorStr = colorStr;
      _updatePaint(colorStr);
    }
  }

  void _updatePaint(String colorStr) {
    Color newColor;
    switch (colorStr) {
      case 'green':
        newColor = Colors.greenAccent;
        break;
      case 'purple':
        newColor = Colors.purpleAccent;
        break;
      case 'blue':
        newColor = Colors.cyanAccent;
        break;
      case 'red':
      default:
        newColor = Colors.redAccent;
        break;
    }
    _sprite.paint = Paint()..color = newColor;
  }
}