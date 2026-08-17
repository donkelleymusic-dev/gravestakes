import 'package:flame/components.dart';
import 'package:flame/palette.dart';

class RemotePlayer extends PositionComponent {
  RemotePlayer() : super(size: Vector2.all(32.0), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    add(
      RectangleComponent(
        size: size,
        paint: BasicPalette.blue.paint(), 
      ),
    );
  }

  void updatePosition(double x, double y, double newAngle) {
    position = Vector2(x, y);
    angle = newAngle;
  }
}