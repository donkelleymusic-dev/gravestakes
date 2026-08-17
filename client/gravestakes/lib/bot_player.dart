import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/palette.dart';
import 'game.dart';

class BotPlayer extends PositionComponent with HasGameReference<GraveStakesGame> {
  final double maxSpeed = 120.0; 
  final Random _random = Random();

  Vector2 movementDelta = Vector2.zero();
  double directionTimer = 0;

  bool isStunned = false;
  double stunTimer = 0;
  double attackCooldown = 0;

  double networkTick = 0; 
  final double networkRate = 0.05; // Broadcast 20 times a second

  BotPlayer() : super(size: Vector2.all(32.0), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    add(RectangleComponent(size: size, paint: BasicPalette.blue.paint()));
    _chooseNewDirection();
  }

  void applyStun(double duration) {
    isStunned = true;
    stunTimer = duration;
  }

  void _chooseNewDirection() {
    final angle = _random.nextDouble() * 2 * pi;
    movementDelta = Vector2(cos(angle), sin(angle));
    directionTimer = 2.0 + _random.nextDouble() * 3.0; 
  }

  @override
  void update(double dt) {
    if (!game.gameStarted) return; 
    super.update(dt);

    // IF WE ARE NOT THE HOST, DO NOT RUN AI MATH!
    if (!game.isHost) return;

    if (isStunned) {
      stunTimer -= dt;
      if (stunTimer <= 0) isStunned = false;
      return; 
    }

    directionTimer -= dt;
    if (directionTimer <= 0) {
      _chooseNewDirection();
    }

    // Apply movement with wall collisions
    final potentialPosition = position + (movementDelta * maxSpeed * dt);

    final testX = Vector2(potentialPosition.x, position.y);
    if (!game.gameMap.checkCollision(testX, size)) {
      position.x = potentialPosition.x;
    } else {
      _chooseNewDirection(); // Pick a new path if we hit a wall
    }

    final testY = Vector2(position.x, potentialPosition.y);
    if (!game.gameMap.checkCollision(testY, size)) {
      position.y = potentialPosition.y;
    } else {
      _chooseNewDirection();
    }

    angle = movementDelta.screenAngle();

    // Attack logic
    if (attackCooldown > 0) attackCooldown -= dt;

    final human = game.player;
    final distance = position.distanceTo(human.position);

    if (distance < 150 && attackCooldown <= 0 && !human.isStunned) {
      game.jumpScareEffect.trigger(); 
      human.applyStun(2.0);              
      attackCooldown = 8.0;              
    }

    // ONLY the Host broadcasts bot movements!
    if (game.isHost) {
      networkTick += dt;
      if (networkTick >= networkRate) {
        networkTick = 0;
        
        final botIndex = game.bots.indexOf(this); 
        if (botIndex != -1) {
          game.myChannel.sendBroadcastMessage(
            event: 'bot_move',
            payload: {
              'index': botIndex,
              'x': position.x,
              'y': position.y,
              'a': angle,
            },
          );
        }
      }
    }
  }
}