import 'package:flame/components.dart';
import 'package:flame/collisions.dart';
import 'player.dart';
import 'game.dart';

class SpookyBox extends SpriteComponent with HasGameReference<GraveStakesGame>, CollisionCallbacks {
  final String id;

  SpookyBox({required this.id, required Vector2 position})
      : super(position: position, size: Vector2.all(32), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    // Give the box true 2.5D depth so it renders in front of walls behind it!
    priority = ((position.y + 16) * 10).toInt();

    // 1. Grab the specific spritesheet from Flame's memory cache
    final spritesheet = game.images.fromCache('Base_BaseChip_pipo.png'); 

    // 2. Crop out the exact 32x32 chest using your Tiled coordinates!
    sprite = Sprite(
      spritesheet,
      srcPosition: Vector2(192.0, 3424.0), // The X and Y you found
      srcSize: Vector2(32.0, 32.0),        // The W and H you found
    );
    
    // Add a hitbox so the player can collide with it
    add(RectangleHitbox());
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);

    // If our LOCAL player touches it, tell the network we are claiming it!
    if (other is Player && !other.isStunned) {
      game.claimSpookyBox(id);
    }
  }
}