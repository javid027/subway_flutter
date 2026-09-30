import 'dart:ui';

import 'package:flame/components.dart';

import '../game_state.dart';
import '../runner_game.dart';

/// Draws the pseudo-3D scene behind every gameplay component: a sky that
/// blends between day and night as the run progresses, a paved road with
/// dashed lane markings that converges to a vanishing point, and roadside
/// poles/trees/buildings receding into the distance. Every element is
/// positioned with the exact same depth-to-screen projection as
/// [Player]/[Chaser]/[Obstacle] (see `RunnerGame`'s perspective camera
/// section), so the whole scene reads as one consistent 3D-ish space
/// rather than a flat 2D backdrop.
class Road extends PositionComponent with HasGameReference<RunnerGame> {
  /// Near/far range the paved surface is drawn across (matches the sky
  /// boundary at the far end, so there's no visible seam or "dead zone").
  static const double roadNearZ = -1.5;
  static const double trueFarZ = 55.0;

  /// World-depth size of one dashed lane-marking segment (mark + gap).
  static const double laneMarkDepth = 0.6;
  static const double laneMarkGap = 0.55;
  static const double laneMarkPeriod = laneMarkDepth + laneMarkGap;
  static const double laneMarkHalfWidthFraction = 0.013;

  /// World-depth spacing for the faint pavement seams (expansion joints).
  static const double seamSpacing = 2.2;

  /// Depth range for the parallax lamp posts right at the track's edge.
  static const double poleSpacing = 2.4;
  static const double poleFarZ = 22.0;
  static const double poleNearZ = -1.5;

  /// Depth range for the trees/buildings further out in the background.
  static const double scenerySpacing = 4.2;
  static const double sceneryFarZ = 34.0;
  static const double sceneryNearZ = -1.5;

  double _laneMarkScrollZ = 0;
  double _seamScrollZ = 0;
  double _poleScrollZ = 0;
  double _sceneryScrollZ = 0;

  // Day/night color pairs. [Road] blends between these each frame using
  // `game.dayNightT` (0 = day, 1 = night) rather than switching instantly.
  static const _skyTopDay = Color(0xFF4FC3F7);
  static const _skyHorizonDay = Color(0xFFFFE0B2);
  static const _skyTopNight = Color(0xFF0D0D16);
  static const _skyHorizonNight = Color(0xFF3E3A56);

  static const _shoulderDay = Color(0xFF6AB04C);
  static const _shoulderNight = Color(0xFF1E1E24);

  static const _roadSurfaceDay = Color(0xFF62626A);
  static const _roadSurfaceNight = Color(0xFF242429);

  static const _curbDay = Color(0xFFECEFF1);
  static const _curbNight = Color(0xFFB0BEC5);

  static const _laneMarkColor = Color(0xFFFFCA28);
  static const _seamColor = Color(0x2EFFFFFF);

  static const _treeTrunk = Color(0xFF6D4C41);
  static const _treeFoliageDay = Color(0xFF43A047);
  static const _treeFoliageNight = Color(0xFF1B3A1D);

  static const List<Color> _buildingWallsDay = [
    Color(0xFFFFAB91),
    Color(0xFF90CAF9),
    Color(0xFFCE93D8),
    Color(0xFFA5D6A7),
  ];
  static const _buildingSilhouetteNight = Color(0xFF17171F);
  static const _buildingWindowLit = Color(0xFFFFE082);

  final Paint _poleShadowPaint = Paint()..color = const Color(0x33000000);

  @override
  void update(double dt) {
    super.update(dt);
    if (game.state == GameState.running) {
      final speed = game.worldSpeed;
      _laneMarkScrollZ = (_laneMarkScrollZ + speed * dt) % laneMarkPeriod;
      _seamScrollZ = (_seamScrollZ + speed * dt) % seamSpacing;
      _poleScrollZ = (_poleScrollZ + speed * dt) % poleSpacing;
      _sceneryScrollZ = (_sceneryScrollZ + speed * dt) % scenerySpacing;
    }
  }

  @override
  void render(Canvas canvas) {
    final size = game.size;
    final t = game.dayNightT;

    final skyTop = Color.lerp(_skyTopDay, _skyTopNight, t)!;
    final skyHorizon = Color.lerp(_skyHorizonDay, _skyHorizonNight, t)!;
    final shoulder = Color.lerp(_shoulderDay, _shoulderNight, t)!;
    final roadSurface = Color.lerp(_roadSurfaceDay, _roadSurfaceNight, t)!;
    final curb = Color.lerp(_curbDay, _curbNight, t)!;

    _drawSky(canvas, size, skyTop, skyHorizon);
    final horizonScreenY = game.screenYForZ(trueFarZ);
    canvas.drawRect(
      Rect.fromLTWH(0, horizonScreenY, size.x, size.y - horizonScreenY),
      Paint()..color = shoulder,
    );

    _drawScenery(canvas, t);
    _drawRoadSurface(canvas, roadSurface, skyHorizon);
    _drawPavementSeams(canvas);
    _drawLaneMarkings(canvas);
    _drawPoles(canvas, t);
    _drawRoadEdges(canvas, curb);
  }

  void _drawSky(Canvas canvas, Vector2 size, Color top, Color horizon) {
    final horizonScreenY = game.screenYForZ(trueFarZ);
    final rect = Rect.fromLTWH(0, 0, size.x, horizonScreenY);
    final shader = Gradient.linear(
      const Offset(0, 0),
      Offset(0, horizonScreenY),
      [top, horizon],
    );
    canvas.drawRect(rect, Paint()..shader = shader);
    // A soft glow right at the vanishing point sells the horizon line.
    canvas.drawRect(
      Rect.fromLTWH(0, horizonScreenY - 14, size.x, 14),
      Paint()
        ..shader = Gradient.linear(
          Offset(0, horizonScreenY - 14),
          Offset(0, horizonScreenY),
          [horizon.withAlpha(0), horizon.withAlpha(160)],
        ),
    );
  }

  /// The paved surface, drawn as a single trapezoid from the near plane
  /// all the way to the horizon and blended into the sky's horizon color
  /// at the far edge — no per-tile detail, since a real road doesn't have
  /// any and it reads far more like an actual street than a tiled floor.
  void _drawRoadSurface(Canvas canvas, Color surface, Color skyHorizon) {
    final nearScale = game.scaleForZ(roadNearZ);
    final farScale = game.scaleForZ(trueFarZ);
    final nearY = game.screenYForZ(roadNearZ);
    final farY = game.screenYForZ(trueFarZ);
    final centerX = game.centerX;
    final halfWidth = game.roadNearHalfWidth;

    final path = Path()
      ..moveTo(centerX - halfWidth * nearScale, nearY)
      ..lineTo(centerX + halfWidth * nearScale, nearY)
      ..lineTo(centerX + halfWidth * farScale, farY)
      ..lineTo(centerX - halfWidth * farScale, farY)
      ..close();

    final shader = Gradient.linear(
      Offset(centerX, nearY),
      Offset(centerX, farY),
      [surface, skyHorizon],
    );
    canvas.drawPath(path, Paint()..shader = shader);
  }

  /// Faint expansion-joint seams spanning the road, scrolling toward the
  /// camera — a subtle continuous-motion cue that doesn't read as a
  /// checkerboard or train-track pattern the way tiled rows did.
  void _drawPavementSeams(Canvas canvas) {
    final paint = Paint()
      ..color = _seamColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final centerX = game.centerX;
    final halfWidth = game.roadNearHalfWidth;

    var index = (roadNearZ / seamSpacing).floor() - 1;
    while (true) {
      final z = index * seamSpacing - _seamScrollZ;
      if (z > trueFarZ) break;
      if (z >= roadNearZ) {
        final scale = game.scaleForZ(z);
        final y = game.screenYForZ(z);
        canvas.drawLine(
          Offset(centerX - halfWidth * scale, y),
          Offset(centerX + halfWidth * scale, y),
          paint,
        );
      }
      index++;
    }
  }

  /// Two dashed lane-divider lines, drawn the same way the old checker
  /// rows were — a perspective-correct quad per dash — but as thin strokes
  /// down the two lane boundaries instead of filling the whole surface.
  void _drawLaneMarkings(Canvas canvas) {
    final paint = Paint()..color = _laneMarkColor;
    for (final laneOffsetFrac in [-1.0 / 3.0, 1.0 / 3.0]) {
      var index = (roadNearZ / laneMarkPeriod).floor() - 1;
      while (true) {
        final nearZ = index * laneMarkPeriod - _laneMarkScrollZ;
        final farZ = nearZ + laneMarkDepth;
        if (nearZ > trueFarZ) break;
        if (farZ >= roadNearZ) {
          _drawLaneMarkSegment(canvas, laneOffsetFrac, nearZ, farZ, paint);
        }
        index++;
      }
    }
  }

  void _drawLaneMarkSegment(
    Canvas canvas,
    double offsetFrac,
    double nearZ,
    double farZ,
    Paint paint,
  ) {
    final nearScale = game.scaleForZ(nearZ);
    final farScale = game.scaleForZ(farZ);
    final nearY = game.screenYForZ(nearZ);
    final farY = game.screenYForZ(farZ);
    final centerX = game.centerX;
    final halfWidth = game.roadNearHalfWidth;
    const half = laneMarkHalfWidthFraction;

    final path = Path()
      ..moveTo(centerX + (offsetFrac - half) * halfWidth * nearScale, nearY)
      ..lineTo(centerX + (offsetFrac + half) * halfWidth * nearScale, nearY)
      ..lineTo(centerX + (offsetFrac + half) * halfWidth * farScale, farY)
      ..lineTo(centerX + (offsetFrac - half) * halfWidth * farScale, farY)
      ..close();
    canvas.drawPath(path, paint);
  }

  /// The two converging curb lines marking the edge of the road, drawn as
  /// a simple straight-edged trapezoid all the way from the near plane to
  /// the horizon (matching the sky boundary, so there's no visible gap).
  void _drawRoadEdges(Canvas canvas, Color curb) {
    final nearScale = game.scaleForZ(roadNearZ);
    final farScale = game.scaleForZ(trueFarZ);
    final nearY = game.screenYForZ(roadNearZ);
    final farY = game.screenYForZ(trueFarZ);
    final centerX = game.centerX;
    final halfWidth = game.roadNearHalfWidth;

    for (final side in [-1.0, 1.0]) {
      final path = Path()
        ..moveTo(centerX + side * halfWidth * nearScale, nearY)
        ..lineTo(centerX + side * halfWidth * farScale, farY);
      canvas.drawPath(
        path,
        Paint()
          ..color = curb
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  /// Lamp posts right at the track's edge, positioned and scaled with the
  /// same projection as everything else so they shrink into the distance.
  void _drawPoles(Canvas canvas, double dayNightT) {
    final capColor = Color.lerp(
      const Color(0xFFBDBDBD),
      const Color(0xFFFFD54F),
      dayNightT,
    )!;
    final polePaint = Paint()..color = const Color(0xFF3D3D4A);
    final capPaint = Paint()..color = capColor;

    var poleIndex = (poleNearZ / poleSpacing).floor() - 1;
    while (true) {
      final z = poleIndex * poleSpacing - _poleScrollZ;
      if (z > poleFarZ) break;
      if (z >= poleNearZ) {
        _drawPolePair(canvas, z, polePaint, capPaint);
      }
      poleIndex++;
    }
  }

  void _drawPolePair(Canvas canvas, double z, Paint polePaint, Paint capPaint) {
    final scale = game.scaleForZ(z);
    final y = game.screenYForZ(z);
    final centerX = game.centerX;
    final lateralOffset = game.roadNearHalfWidth * 1.14 * scale;

    _drawPole(canvas, centerX - lateralOffset, y, scale, polePaint, capPaint);
    _drawPole(canvas, centerX + lateralOffset, y, scale, polePaint, capPaint);
  }

  void _drawPole(
    Canvas canvas,
    double x,
    double y,
    double scale,
    Paint polePaint,
    Paint capPaint,
  ) {
    final width = 6.0 * scale;
    final height = 46.0 * scale;
    if (x < -width || x > game.size.x + width) return;

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(x, y),
        width: 14 * scale,
        height: 5 * scale,
      ),
      _poleShadowPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(x - width / 2, y - height, width, height),
      polePaint,
    );
    canvas.drawCircle(Offset(x, y - height), 5 * scale, capPaint);
  }

  /// Trees and simple buildings further back in the shoulders, alternating
  /// by index and receding into the distance with the same projection as
  /// everything else — reinforces forward motion and depth without
  /// per-object detail expensive enough to cost frame time.
  void _drawScenery(Canvas canvas, double dayNightT) {
    var index = (sceneryNearZ / scenerySpacing).floor() - 1;
    while (true) {
      final z = index * scenerySpacing - _sceneryScrollZ;
      if (z > sceneryFarZ) break;
      if (z >= sceneryNearZ) {
        _drawSceneryPair(canvas, index, z, dayNightT);
      }
      index++;
    }
  }

  void _drawSceneryPair(Canvas canvas, int index, double z, double dayNightT) {
    final scale = game.scaleForZ(z);
    final y = game.screenYForZ(z);
    final centerX = game.centerX;
    final lateralOffset = game.roadNearHalfWidth * 1.55 * scale;
    final isTree = index.isEven;

    if (isTree) {
      _drawTree(canvas, centerX - lateralOffset, y, scale, dayNightT);
      _drawTree(canvas, centerX + lateralOffset, y, scale, dayNightT);
    } else {
      _drawBuilding(canvas, centerX - lateralOffset, y, scale, index, dayNightT);
      _drawBuilding(canvas, centerX + lateralOffset, y, scale, index, dayNightT);
    }
  }

  void _drawTree(Canvas canvas, double x, double y, double scale, double dayNightT) {
    final trunkWidth = 6.0 * scale;
    final trunkHeight = 18.0 * scale;
    final foliageRadius = 16.0 * scale;
    if (x < -foliageRadius || x > game.size.x + foliageRadius) return;

    canvas.drawRect(
      Rect.fromLTWH(x - trunkWidth / 2, y - trunkHeight, trunkWidth, trunkHeight),
      Paint()..color = _treeTrunk,
    );
    canvas.drawCircle(
      Offset(x, y - trunkHeight - foliageRadius * 0.7),
      foliageRadius,
      Paint()..color = Color.lerp(_treeFoliageDay, _treeFoliageNight, dayNightT)!,
    );
  }

  void _drawBuilding(
    Canvas canvas,
    double x,
    double y,
    double scale,
    int index,
    double dayNightT,
  ) {
    final width = 34.0 * scale;
    // Vary height a bit per index so the skyline isn't perfectly uniform.
    final height = (60.0 + (index * 37) % 40) * scale;
    if (x < -width || x > game.size.x + width) return;

    final wallColor = Color.lerp(
      _buildingWallsDay[index.abs() % _buildingWallsDay.length],
      _buildingSilhouetteNight,
      dayNightT,
    )!;
    final rect = Rect.fromLTWH(x - width / 2, y - height, width, height);
    canvas.drawRect(rect, Paint()..color = wallColor);

    // A few simple windows; lit at night, blank by day.
    final windowColor = _buildingWindowLit.withAlpha((dayNightT * 255).round());
    if (windowColor.a > 0) {
      const cols = 3;
      final rows = (height / (14 * scale)).floor().clamp(1, 6);
      final windowSize = 5.0 * scale;
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          final wx = rect.left + width * (c + 1) / (cols + 1) - windowSize / 2;
          final wy = rect.top + 10 * scale + r * 14 * scale;
          if (wy + windowSize > rect.bottom) continue;
          canvas.drawRect(
            Rect.fromLTWH(wx, wy, windowSize, windowSize),
            Paint()..color = windowColor,
          );
        }
      }
    }
  }
}
