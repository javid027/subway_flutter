import 'dart:math';
import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';

import '../game_state.dart';
import '../runner_game.dart';

/// A collectible coin. Spawns and travels exactly like [Obstacle] (same
/// depth projection), but collecting one just adds to the coin count
/// instead of ending the run.
class Coin extends PositionComponent with HasGameReference<RunnerGame> {
  static const double diameter = 30;

  static const double spawnZ = 10.0;
  static const double removeZ = -1.3;

  final int laneIndex;

  double _z;
  double _spinCycle = 0;
  bool _collected = false;

  final Paint _coinRimPaint = Paint()..color = const Color(0xFFF9A825);
  final Paint _starPaint = Paint()..color = const Color(0xFFFFF8E1);
  final Paint _outlinePaint = Paint()
    ..color = const Color(0xFFB8720C)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6;
  final Paint _shinePaint = Paint()..color = const Color(0x99FFFFFF);

  Coin({required this.laneIndex, double startZ = spawnZ})
      : _z = startZ,
        super(
          size: Vector2.all(diameter),
          anchor: Anchor.center,
          priority: 1,
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(CircleHitbox());
    _applyTransform();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (game.state != GameState.running) return;
    _spinCycle += dt * 6;
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

  /// Called by [Player] on overlap; awards the coin exactly once.
  void collect() {
    if (_collected) return;
    _collected = true;
    game.onCoinCollected();
    removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    // A cheap "spin" by squashing horizontally, rather than a real 3D flip.
    final squash = cos(_spinCycle).abs().clamp(0.15, 1.0);
    final center = Offset(size.x / 2, size.y / 2);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(squash, 1.0);
    canvas.translate(-center.dx, -center.dy);

    final radius = size.x / 2;
    canvas.drawCircle(center, radius, _coinRimPaint);
    canvas.drawCircle(
      center,
      radius * 0.78,
      Paint()
        ..shader = Gradient.radial(
          center - Offset(radius * 0.2, radius * 0.2),
          radius,
          const [Color(0xFFFFE082), Color(0xFFFFC107)],
        ),
    );
    _drawStar(canvas, center, radius * 0.4);
    canvas.drawCircle(
      center - Offset(radius * 0.28, radius * 0.28),
      radius * 0.16,
      _shinePaint,
    );
    canvas.drawCircle(center, radius, _outlinePaint);

    canvas.restore();
  }

  void _drawStar(Canvas canvas, Offset center, double r) {
    final path = Path();
    for (var i = 0; i < 5; i++) {
      final outerAngle = -pi / 2 + i * 2 * pi / 5;
      final innerAngle = outerAngle + pi / 5;
      final outer = center + Offset(cos(outerAngle), sin(outerAngle)) * r;
      final inner =
          center + Offset(cos(innerAngle), sin(innerAngle)) * (r * 0.45);
      if (i == 0) {
        path.moveTo(outer.dx, outer.dy);
      } else {
        path.lineTo(outer.dx, outer.dy);
      }
      path.lineTo(inner.dx, inner.dy);
    }
    path.close();
    canvas.drawPath(path, _starPaint);
  }
}
