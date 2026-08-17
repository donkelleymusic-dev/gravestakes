import 'package:flame/components.dart';
import 'package:flame/palette.dart';

class Player extends PositionComponent {
  final JoystickComponent joystick;
  final double maxSpeed = 200.0; // Pixels per second

  Player(this.joystick) : super(size: Vector2.all(32.0), anchor: Anchor.center);

  @override
  Future onLoad() async {
    // Placeholder graphic: A red square until we add pixel art
    add(
      RectangleComponent(
        size: size,
        paint: BasicPalette.red.paint(),
      ),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);

    // If the joystick is being dragged
    if (!joystick.delta.isZero()) {
      // Move the player based on joystick intensity and time delta
      position.add(joystick.relativeDelta * maxSpeed * dt);
      
      // Rotate the player to face the direction they are moving.
      // This is critical for our flashlight cone later.
      angle = joystick.delta.screenAngle();
    }
  }
}