import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';

import '../game_state.dart';
import '../runner_game.dart';

/// The policeman chasing the player from behind. In this over-the-shoulder
/// camera, "behind the player" means closer to the viewer than the player —
/// obstacles are ahead and approach from the top of the screen, while the
/// chaser trails below the player, closing in from the bottom. It keeps a
/// steady distance while the game is running, and rushes forward to "catch"
/// the player once a collision ends the run.
///
/// Drawn from BEHIND, same as [Player] and for the same reason: both
/// characters are running away from the camera, so we see the backs of
/// their heads, not their faces. The police cap's crown + back strap (no
/// visor — that's on the far side) and the bulky navy uniform are what
/// distinguish this silhouette from the player's at a glance.
class Chaser extends PositionComponent with HasGameReference<RunnerGame> {
  static const double defaultWidth = 58;
  static const double defaultHeight = 78;

  /// Depth gap (world z units) kept behind the player during normal play;
  /// since it's closer to the camera than [RunnerGame.zPlayer], the chaser
  /// renders lower on screen and larger, matching "right behind you."
  static const double normalGapZ = 1.15;

  /// Gap at which the chaser is considered to have caught the player.
  static const double caughtGapZ = 0.05;

  /// How fast the depth gap closes once [startCatchUp] is triggered.
  static const double catchUpSpeed = 1.6;

  /// How quickly the chaser mirrors the player's lane position.
  static const double followRate = 6;

  double _gapZ = normalGapZ;
  bool _catchingUp = false;

  /// The chaser's own interpolated lane position, easing toward the
  /// player's so it visually trails a beat behind lane changes too.
  double _followFraction = (RunnerGame.laneCount - 1) / 2;

  /// Counts up while running; drives the running-stride and bob animation.
  double _runCycle = 0;

  final Paint _shadowPaint = Paint()..color = const Color(0x66000000);
  final Paint _skinPaint = Paint()..color = const Color(0xFFE8B08A);
  final Paint _skinShadePaint = Paint()..color = const Color(0xFFD1926A);
  final Paint _uniformPaint = Paint()..color = const Color(0xFF2C3E67);
  final Paint _uniformDarkPaint = Paint()..color = const Color(0xFF1E2A4A);
  final Paint _beltPaint = Paint()..color = const Color(0xFF2B2B2B);
  final Paint _badgePaint = Paint()..color = const Color(0xFFFFD54F);
  final Paint _outlinePaint = Paint()
    ..color = const Color(0xFF12121A)
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round;

  Chaser()
      : super(
          size: Vector2(defaultWidth, defaultHeight),
          anchor: Anchor.center,
          // Renders above the player: the chaser sits closer to the camera
          // (see class doc), so it should visually occlude the player when
          // the two overlap during the catch-up sequence.
          priority: 4,
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    reset();
  }

  /// Returns the chaser to its resting distance behind the player.
  void reset() {
    _gapZ = normalGapZ;
    _catchingUp = false;
    _runCycle = 0;
    _followFraction = game.player.laneFraction;
    final z = RunnerGame.zPlayer - _gapZ;
    scale = Vector2.all(game.scaleForZ(z));
    position = Vector2(
      game.screenXForLaneFraction(_followFraction, z),
      game.screenYForZ(z),
    );
  }

  /// Begins closing the distance to the player after a collision.
  void startCatchUp() {
    _catchingUp = true;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (game.state != GameState.running && !_catchingUp) return;

    _runCycle += dt * 11;

    if (_catchingUp) {
      _gapZ -= catchUpSpeed * dt;
      if (_gapZ <= caughtGapZ) {
        _gapZ = caughtGapZ;
        _catchingUp = false;
        game.onChaserCaughtPlayer();
      }
    }

    final dFraction = game.player.laneFraction - _followFraction;
    _followFraction += dFraction * (followRate * dt).clamp(0.0, 1.0);

    final z = RunnerGame.zPlayer - _gapZ;
    scale = Vector2.all(game.scaleForZ(z));
    position = Vector2(
      game.screenXForLaneFraction(_followFraction, z),
      game.screenYForZ(z),
    );
  }

  @override
  void render(Canvas canvas) {
    final stride = sin(_runCycle);
    final bob = stride.abs() * size.y * 0.02;
    final legSwing = stride * size.y * 0.07;
    final armSwing = -stride * size.x * 0.14;
    final centerX = size.x / 2;

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX, size.y - 4),
        width: size.x * 0.66,
        height: 9,
      ),
      _shadowPaint,
    );

    canvas.save();
    canvas.translate(0, -bob);

    final hipY = size.y * 0.64;
    final shoulderY = size.y * 0.36;
    final headCenterY = size.y * 0.19;
    final headRadius = size.x * 0.24;

    // A small alternating full-body lean synced to the stride, matching
    // the player's — reads as running rather than gliding along.
    final bodyTilt = stride * 0.06;
    canvas.save();
    canvas.translate(centerX, hipY);
    canvas.rotate(bodyTilt);
    canvas.translate(-centerX, -hipY);

    // Legs (dark uniform trousers), bulkier stance than the player's.
    _drawLimb(
      canvas,
      Offset(centerX - size.x * 0.16, hipY - legSwing * 0.5),
      Offset(centerX - size.x * 0.18, size.y * 0.98 + legSwing),
      size.x * 0.19,
      _uniformDarkPaint,
    );
    _drawLimb(
      canvas,
      Offset(centerX + size.x * 0.16, hipY + legSwing * 0.5),
      Offset(centerX + size.x * 0.18, size.y * 0.98 - legSwing),
      size.x * 0.19,
      _uniformDarkPaint,
    );

    // Broad torso (navy uniform jacket, back view).
    final torsoRect = Rect.fromLTRB(
      centerX - size.x * 0.36,
      shoulderY,
      centerX + size.x * 0.36,
      hipY + size.y * 0.06,
    );
    final torsoRRect =
        RRect.fromRectAndRadius(torsoRect, Radius.circular(size.x * 0.16));
    canvas.drawRRect(
      torsoRRect,
      Paint()
        ..shader = Gradient.linear(
          torsoRect.topCenter,
          torsoRect.bottomCenter,
          const [Color(0xFF3B4F82), Color(0xFF223259)],
        ),
    );
    canvas.drawRRect(torsoRRect, _outlinePaint..strokeWidth = size.x * 0.03);

    // Belt, with its buckle badge visible from behind.
    final beltRect =
        Rect.fromLTWH(torsoRect.left, hipY - size.y * 0.03, torsoRect.width, size.y * 0.05);
    canvas.drawRect(beltRect, _beltPaint);
    canvas.drawCircle(beltRect.center, size.x * 0.045, _badgePaint);
    canvas.drawCircle(
      beltRect.center,
      size.x * 0.045,
      _outlinePaint..strokeWidth = size.x * 0.012,
    );

    // Arms, swinging opposite the legs.
    _drawLimb(
      canvas,
      Offset(centerX - size.x * 0.36, shoulderY + 2),
      Offset(centerX - size.x * 0.44 + armSwing, hipY - 2),
      size.x * 0.15,
      _uniformPaint,
    );
    _drawLimb(
      canvas,
      Offset(centerX + size.x * 0.36, shoulderY + 2),
      Offset(centerX + size.x * 0.44 - armSwing, hipY - 2),
      size.x * 0.15,
      _uniformPaint,
    );

    // Back of the head, with a soft shaded edge for volume (same
    // offset-circle trick as the player, so it can never draw outside the
    // head's silhouette), plus ears so it doesn't read as a blank circle.
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
    for (final sign in [-1.0, 1.0]) {
      final earCenter = headCenter + Offset(sign * headRadius * 0.9, headRadius * 0.1);
      canvas.drawCircle(earCenter, headRadius * 0.17, _skinPaint);
      canvas.drawCircle(earCenter, headRadius * 0.17, _outlinePaint..strokeWidth = headRadius * 0.05);
    }

    // Peaked police cap, seen from behind: a flatter crown + band than the
    // player's cap (no visor — that's on the far side), plus a back strap
    // with its adjuster buckle. The distinct navy silhouette and bulkier
    // build are what set this character apart from the player at a glance.
    final bandCenterY = headCenterY - headRadius * 0.62;
    final topRect = Rect.fromCenter(
      center: Offset(centerX, bandCenterY - headRadius * 0.28),
      width: headRadius * 1.85,
      height: headRadius * 0.85,
    );
    canvas.drawOval(topRect, _uniformDarkPaint);
    canvas.drawOval(topRect, _outlinePaint..strokeWidth = headRadius * 0.07);

    final bandRect = Rect.fromCenter(
      center: Offset(centerX, bandCenterY),
      width: headRadius * 2.0,
      height: headRadius * 0.62,
    );
    final bandRRect =
        RRect.fromRectAndRadius(bandRect, Radius.circular(headRadius * 0.2));
    canvas.drawRRect(bandRRect, _uniformDarkPaint);
    canvas.drawRRect(bandRRect, _outlinePaint..strokeWidth = headRadius * 0.07);

    final strapRect = Rect.fromCenter(
      center: Offset(centerX, headCenterY - headRadius * 0.22),
      width: headRadius * 1.3,
      height: headRadius * 0.2,
    );
    canvas.drawRect(strapRect, _uniformDarkPaint);
    canvas.drawRect(strapRect, _outlinePaint..strokeWidth = headRadius * 0.05);
    canvas.drawCircle(strapRect.center, headRadius * 0.1, _badgePaint);
    canvas.drawCircle(
      strapRect.center,
      headRadius * 0.1,
      _outlinePaint..strokeWidth = headRadius * 0.03,
    );

    canvas.restore();
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
}
