import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';

import '../game_state.dart';
import '../runner_game.dart';

/// A single obstacle that spawns far ahead of the player (large `z`, near
/// the horizon) and travels toward the camera as `z` shrinks, growing and
/// dropping down the screen the whole way per the shared perspective
/// projection. Removed once it passes behind the camera.
class Obstacle extends PositionComponent with HasGameReference<RunnerGame> {
  static const double defaultWidth = 52;
  static const double defaultHeight = 46;

  /// Depth at which obstacles are spawned, near the horizon.
  static const double spawnZ = 10.0;

  /// Depth at which an obstacle is considered to have passed the camera
  /// and is removed.
  static const double removeZ = -1.3;

  final int laneIndex;

  double _z = spawnZ;

  final Paint _stripePaint = Paint()..color = const Color(0xFFFFF176);
  final Paint _outlinePaint = Paint()
    ..color = const Color(0xFF7A1E1B)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.4
    ..strokeJoin = StrokeJoin.round;

  Obstacle({required this.laneIndex})
      : super(size: Vector2(defaultWidth, defaultHeight), anchor: Anchor.center, priority: 1);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox());
    _applyTransform();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (game.state != GameState.running) return;
    _z -= game.worldSpeed * dt;
    if (_z < removeZ) {
      removeFromParent();
      return;
    }
    _applyTransform();
  }

  void _applyTransform() {
    scale = Vector2.all(game.scaleForZ(_z));
    position = Vector2(
      game.screenXForLane(laneIndex, _z),
      game.screenYForZ(_z),
    );
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          const [Color(0xFFFF6F6B), Color(0xFFD32F2F)],
        ),
    );

    for (var i = 0; i < 3; i++) {
      final y = size.y * (i + 0.5) / 3 - 3;
      canvas.drawRect(Rect.fromLTWH(4, y, size.x - 8, 6), _stripePaint);
    }

    canvas.drawRRect(rrect, _outlinePaint);
  }
}
