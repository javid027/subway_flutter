import 'dart:math';
import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';

import '../game_state.dart';
import '../runner_game.dart';
import 'coin.dart';
import 'obstacle.dart';

/// The player-controlled runner. Lives in one of the three lanes and
/// smoothly interpolates toward a new lane whenever it changes.
///
/// Drawn from BEHIND, like every character in this camera style (the
/// runner is running away from the camera, into the screen — the same
/// convention real endless runners use). A visible face would mean the
/// character is running toward the viewer, which reads as wrong for this
/// shot, so there's deliberately no face here: just the back of the head,
/// the cap's crown and back strap, and the back of the hoodie.
class Player extends PositionComponent
    with HasGameReference<RunnerGame>, CollisionCallbacks {
  static const double defaultWidth = 48;
  static const double defaultHeight = 72;

  /// How quickly the player closes the gap to its target lane; higher is
  /// snappier. Expressed as a fraction-per-second closed toward the target.
  static const double laneChangeRate = 10;

  /// How long a jump lasts, in seconds.
  static const double jumpDuration = 0.55;

  /// Peak visual height of a jump, in pixels.
  static const double jumpHeight = 70;

  int laneIndex = 1;

  /// Interpolated lane position (0..laneCount-1) used to compute screen X;
  /// separate from [laneIndex] so lane changes glide smoothly instead of
  /// snapping.
  double _laneFraction = 1;
  double _targetLaneFraction = 1;

  /// Current interpolated lane position (0..laneCount-1); read by [Chaser]
  /// so it can reproject the same lane at its own depth.
  double get laneFraction => _laneFraction;

  /// Counts up while running; drives the leg/arm swing animation.
  double _runCycle = 0;

  /// Small vertical bounce (in pixels) synced to each footfall, so the
  /// runner reads as bouncing along rather than gliding/standing still.
  static const double bobAmplitude = 4.0;
  double _bobOffset = 0;

  /// Counts down from [jumpDuration] to 0 while airborne; 0 means grounded.
  double _jumpTime = 0;

  /// Current visual lift above the ground, recomputed each frame from
  /// [_jumpTime]. Used both to offset the component and to keep the shadow
  /// anchored to the ground instead of rising with the character.
  double _jumpLift = 0;

  bool get isJumping => _jumpTime > 0;

  final Paint _shadowPaint = Paint()..color = const Color(0x66000000);
  final Paint _skinPaint = Paint()..color = const Color(0xFFFFCC99);
  final Paint _skinShadePaint = Paint()..color = const Color(0xFFF0AD70);
  final Paint _hairPaint = Paint()..color = const Color(0xFF4E342E);
  final Paint _capDomePaint = Paint()..color = const Color(0xFFE53935);
  final Paint _capStrapPaint = Paint()..color = const Color(0xFF8E1512);
  final Paint _shirtDarkPaint = Paint()..color = const Color(0xFF1E88C7);
  final Paint _pantsPaint = Paint()..color = const Color(0xFF29456B);
  final Paint _outlinePaint = Paint()
    ..color = const Color(0xFF1A1A22)
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round;

  Player()
      : super(
          size: Vector2(defaultWidth, defaultHeight),
          anchor: Anchor.center,
          priority: 2,
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox());
    reset();
  }

  /// Returns the player to the center lane at the base of the road.
  void reset() {
    laneIndex = 1;
    _laneFraction = 1;
    _targetLaneFraction = 1;
    _jumpTime = 0;
    _jumpLift = 0;
    _runCycle = 0;
    _bobOffset = 0;
    scale = Vector2.all(game.scaleForZ(RunnerGame.zPlayer));
    position = Vector2(
      game.screenXForLaneFraction(_laneFraction, RunnerGame.zPlayer),
      game.screenYForZ(RunnerGame.zPlayer),
    );
  }

  void moveLeft() => _changeLane(-1);

  void moveRight() => _changeLane(1);

  /// Starts a jump (if not already airborne) to hop over an obstacle.
  void jump() {
    if (game.state != GameState.running) return;
    if (_jumpTime > 0) return;
    _jumpTime = jumpDuration;
  }

  void _changeLane(int delta) {
    if (game.state != GameState.running) return;
    final newLane = (laneIndex + delta).clamp(0, RunnerGame.laneCount - 1);
    if (newLane == laneIndex) return;
    laneIndex = newLane;
    _targetLaneFraction = laneIndex.toDouble();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (game.state != GameState.running) return;

    _runCycle += dt * 14;
    // Two bounces per full leg-swing cycle: one per footfall.
    _bobOffset =
        isJumping ? 0 : bobAmplitude * (0.5 - 0.5 * cos(_runCycle * 2));

    if (_jumpTime > 0) {
      _jumpTime = (_jumpTime - dt).clamp(0.0, jumpDuration);
      final progress = 1 - (_jumpTime / jumpDuration);
      _jumpLift = jumpHeight * sin(pi * progress);
    } else {
      _jumpLift = 0;
    }

    final dFraction = _targetLaneFraction - _laneFraction;
    if (dFraction.abs() < 0.01) {
      _laneFraction = _targetLaneFraction;
    } else {
      _laneFraction += dFraction * (laneChangeRate * dt).clamp(0.0, 1.0);
    }

    position.x = game.screenXForLaneFraction(_laneFraction, RunnerGame.zPlayer);
    position.y = game.screenYForZ(RunnerGame.zPlayer) - _jumpLift - _bobOffset;
  }

  @override
  void render(Canvas canvas) {
    // Shadow stays anchored to the ground even while the sprite lifts off
    // for a jump, and shrinks/fades the higher the player gets.
    final airFactor = (_jumpLift / jumpHeight).clamp(0.0, 1.0);
    final shadowWidth = size.x * 0.7 * (1 - airFactor * 0.5);
    canvas.save();
    canvas.translate(0, _jumpLift);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.x / 2, size.y - 4),
        width: shadowWidth,
        height: 8,
      ),
      Paint()..color = _shadowPaint.color.withAlpha((0x66 * (1 - airFactor * 0.6)).round()),
    );
    canvas.restore();

    final stride = isJumping ? 0.0 : sin(_runCycle);
    final legSwing = stride * (size.y * 0.12);
    final armSwing = -stride * (size.x * 0.22);
    final tuck = isJumping ? size.y * 0.08 : 0.0;

    final centerX = size.x / 2;
    final hipY = size.y * 0.62;
    final shoulderY = size.y * 0.34;
    final headCenterY = size.y * 0.18;
    final headRadius = size.x * 0.26;

    // A small alternating full-body lean synced to the stride — reads as
    // a runner's natural side-to-side sway rather than a static pose.
    final bodyTilt = isJumping ? 0.0 : stride * 0.07;
    canvas.save();
    canvas.translate(centerX, hipY);
    canvas.rotate(bodyTilt);
    canvas.translate(-centerX, -hipY);

    // Back leg then front leg, both tucked up slightly mid-jump.
    _drawLimb(
      canvas,
      Offset(centerX - size.x * 0.14, hipY - legSwing * 0.5),
      Offset(centerX - size.x * 0.16, size.y * 0.98 - tuck + legSwing),
      size.x * 0.16,
      _pantsPaint,
    );
    _drawLimb(
      canvas,
      Offset(centerX + size.x * 0.14, hipY + legSwing * 0.5),
      Offset(centerX + size.x * 0.16, size.y * 0.98 - tuck - legSwing),
      size.x * 0.16,
      _pantsPaint,
    );

    // Torso (back of a hoodie), shaded with a soft gradient for volume.
    final torsoRect = Rect.fromLTRB(
      centerX - size.x * 0.30,
      shoulderY,
      centerX + size.x * 0.30,
      hipY + size.y * 0.06,
    );
    final torsoRRect =
        RRect.fromRectAndRadius(torsoRect, Radius.circular(size.x * 0.18));
    canvas.drawRRect(
      torsoRRect,
      Paint()
        ..shader = Gradient.linear(
          torsoRect.topCenter,
          torsoRect.bottomCenter,
          const [Color(0xFF4FC3F7), Color(0xFF1E88C7)],
        ),
    );
    canvas.drawRRect(torsoRRect, _outlinePaint..strokeWidth = size.x * 0.035);

    // Hood, resting on the shoulders/neck — the telltale "back of a hoodie"
    // shape, and it doubles as extra evidence this is a back view.
    final hoodRect = Rect.fromCenter(
      center: Offset(centerX, shoulderY + size.x * 0.02),
      width: size.x * 0.42,
      height: size.x * 0.28,
    );
    canvas.drawOval(hoodRect, _shirtDarkPaint);
    canvas.drawOval(hoodRect, _outlinePaint..strokeWidth = size.x * 0.03);

    // Arms, swinging opposite the legs.
    _drawLimb(
      canvas,
      Offset(centerX - size.x * 0.30, shoulderY + 2),
      Offset(centerX - size.x * 0.38 + armSwing, hipY - 2),
      size.x * 0.13,
      _skinPaint,
    );
    _drawLimb(
      canvas,
      Offset(centerX + size.x * 0.30, shoulderY + 2),
      Offset(centerX + size.x * 0.38 - armSwing, hipY - 2),
      size.x * 0.13,
      _skinPaint,
    );

    // Back of the head: a slightly larger offset circle peeking out
    // bottom-right gives a soft shaded edge for volume, without any risk
    // of it drawing outside the head's own silhouette.
    final headCenter = Offset(centerX, headCenterY);
    canvas.drawCircle(
      headCenter + Offset(headRadius * 0.1, headRadius * 0.1),
      headRadius,
      _skinShadePaint,
    );
    canvas.drawCircle(headCenter, headRadius * 0.96, _skinPaint);
    canvas.drawCircle(
      headCenter,
      headRadius * 0.96,
      _outlinePaint..strokeWidth = headRadius * 0.09,
    );

    // Ears peeking out either side — a small, cheap detail that keeps the
    // back of the head from reading as a plain blank circle.
    for (final sign in [-1.0, 1.0]) {
      final earCenter = headCenter + Offset(sign * headRadius * 0.92, headRadius * 0.08);
      canvas.drawCircle(earCenter, headRadius * 0.16, _skinPaint);
      canvas.drawCircle(earCenter, headRadius * 0.16, _outlinePaint..strokeWidth = headRadius * 0.05);
    }

    // A little hair peeking out at the nape, below the cap.
    final hairRect = Rect.fromCenter(
      center: Offset(centerX, headCenterY + headRadius * 0.72),
      width: headRadius * 1.15,
      height: headRadius * 0.5,
    );
    canvas.drawPath(
      Path()
        ..addArc(hairRect, 0, pi)
        ..close(),
      _hairPaint,
    );

    // Cap, seen from behind: just the rounded crown (no brim — that's on
    // the far side, facing away from the camera) plus a back strap with
    // its little adjuster buckle, the classic snapback silhouette.
    final capRect = Rect.fromCenter(
      center: Offset(centerX, headCenterY - headRadius * 0.28),
      width: headRadius * 2.1,
      height: headRadius * 1.7,
    );
    final capPath = Path()
      ..addArc(capRect, pi, pi)
      ..close();
    canvas.drawPath(capPath, _capDomePaint);
    canvas.drawPath(capPath, _outlinePaint..strokeWidth = headRadius * 0.09);

    final strapRect = Rect.fromCenter(
      center: Offset(centerX, headCenterY - headRadius * 0.32),
      width: headRadius * 1.5,
      height: headRadius * 0.22,
    );
    canvas.drawRect(strapRect, _capStrapPaint);
    canvas.drawRect(strapRect, _outlinePaint..strokeWidth = headRadius * 0.06);
    canvas.drawCircle(strapRect.center, headRadius * 0.09, _capStrapPaint);
    canvas.drawCircle(
      strapRect.center,
      headRadius * 0.09,
      _outlinePaint..strokeWidth = headRadius * 0.03,
    );

    canvas.restore();
  }

  void _drawLimb(
    Canvas canvas,
    Offset from,
    Offset to,
    double thickness,
    Paint paint,
  ) {
    canvas.drawLine(
      from,
      to,
      paint
        ..strokeWidth = thickness
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
    canvas.drawLine(
      from,
      to,
      Paint()
        ..color = _outlinePaint.color
        ..strokeWidth = thickness + 2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke
        ..blendMode = BlendMode.dstOver,
    );
    paint.style = PaintingStyle.fill;
  }

  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    super.onCollisionStart(intersectionPoints, other);
    if (game.state != GameState.running) return;
    if (other is Obstacle && !isJumping) {
      game.onPlayerHitObstacle();
    } else if (other is Coin) {
      other.collect();
    }
  }
}
