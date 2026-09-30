import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;

import 'components/chaser.dart';
import 'components/player.dart';
import 'components/road.dart';
import 'game_state.dart';
import 'systems/audio_manager.dart';
import 'systems/coin_manager.dart';
import 'systems/obstacle_manager.dart';
import 'systems/score_manager.dart';

/// The Flame game powering the endless runner: owns the road, player,
/// chaser and obstacle spawner, and exposes Start/Stop/Restart controls
/// plus reactive state for the Flutter UI overlays to listen to.
class RunnerGame extends FlameGame with HasCollisionDetection, KeyboardEvents {
  static const int laneCount = 3;

  /// Forward speed of the world, in logical pixels per second. Obstacles and
  /// the road scroll toward the player at this rate. Ramps up gradually
  /// while running (see [update]) for a sense of building difficulty, and
  /// resets to [initialGameSpeed] on every new run.
  double gameSpeed = initialGameSpeed;

  static const double initialGameSpeed = 300.0;
  static const double maxGameSpeed = 620.0;

  /// How much [gameSpeed] increases per second of running.
  static const double speedRampPerSecond = 3.5;

  final AudioManager audioManager = AudioManager();
  final ScoreManager scoreManager = ScoreManager();

  late final Road road;
  late final ObstacleManager obstacleManager;
  late final CoinManager coinManager;
  late final Player player;
  late final Chaser chaser;

  final ValueNotifier<GameState> stateNotifier =
      ValueNotifier(GameState.ready);
  final ValueNotifier<int> distanceNotifier = ValueNotifier(0);
  final ValueNotifier<int> bestDistanceNotifier = ValueNotifier(0);
  final ValueNotifier<int> coinsNotifier = ValueNotifier(0);

  /// How many meters make up half a day/night cycle (day→night, then the
  /// same distance again back to day).
  static const double dayNightHalfCycle = 700.0;

  /// 0 = full day, 1 = full night; eased so the transition is gradual
  /// rather than a hard cut. [Road] reads this to blend its palette.
  double get dayNightT {
    final distance = distanceNotifier.value.toDouble();
    final cycle = dayNightHalfCycle * 2;
    final phase = distance % cycle;
    final raw = phase <= dayNightHalfCycle
        ? phase / dayNightHalfCycle
        : (cycle - phase) / dayNightHalfCycle;
    return raw * raw * (3 - 2 * raw);
  }

  double _distanceAccumulator = 0;

  GameState get state => stateNotifier.value;
  set state(GameState value) => stateNotifier.value = value;

  // --- Pseudo-3D perspective camera -----------------------------------
  //
  // Everything (road, player, chaser, obstacles) shares one projection: a
  // component's distance from the camera is a single "depth" value `z`
  // (world units; 0 is the theoretical point directly under the camera,
  // larger is further away/toward the horizon). Depth maps to screen
  // position and scale through the same two formulas used by classic
  // "Mode 7"-style pseudo-3D racers, so the road's converging edges and
  // every object's size line up automatically as they move through z:
  //
  //   scale(z)   = D / (D + z)                        -- shrinks toward 0
  //   screenY(z) = horizonY + (nearY - horizonY) * scale(z)
  //   screenX    = centerX + laneOffsetAtNear * scale(z)
  //
  // `D` ("perspectiveD") is the camera-distance constant: smaller values
  // make things shrink/grow more dramatically as they move through z.

  /// Camera-distance constant controlling how aggressively things scale
  /// with depth. Smaller = more dramatic perspective.
  static const double perspectiveD = 4.5;

  /// Screen-space vanishing point, as a fraction of height.
  static const double horizonYFraction = 0.36;

  /// Screen-space y of the z=0 reference plane, as a fraction of height.
  static const double nearYFraction = 0.97;

  /// Half-width of the road at z=0, as a fraction of screen width.
  static const double roadNearHalfWidthFraction = 0.47;

  /// Depth at which the player stands (obstacles start further away, at
  /// [Obstacle.spawnZ], and travel down to this depth and slightly past).
  static const double zPlayer = 1.3;

  double get centerX => size.x / 2;
  double get horizonY => size.y * horizonYFraction;
  double get nearY => size.y * nearYFraction;
  double get roadNearHalfWidth => size.x * roadNearHalfWidthFraction;

  /// World-depth speed (z units/second) driving obstacle approach and the
  /// road's scroll animation, derived from [gameSpeed] so that single
  /// knob still controls overall pace as the original spec intends.
  double get worldSpeed => gameSpeed / 60;

  double scaleForZ(double z) => perspectiveD / (perspectiveD + z);

  double screenYForZ(double z) =>
      horizonY + (nearY - horizonY) * scaleForZ(z);

  /// Signed offset from the road's centerline at z=0 for a given lane
  /// index (0=left .. laneCount-1=right), before depth scaling.
  double laneOffsetAtNear(int lane) {
    final fraction = (lane - (laneCount - 1) / 2) * (2.0 / laneCount);
    return fraction * roadNearHalfWidth;
  }

  double screenXForLane(int lane, double z) =>
      centerX + laneOffsetAtNear(lane) * scaleForZ(z);

  /// Same as [screenXForLane] but for a fractional (interpolated) lane
  /// position, used while the player is lerping between lanes.
  double screenXForLaneFraction(double laneFraction, double z) {
    final fraction = (laneFraction - (laneCount - 1) / 2) * (2.0 / laneCount);
    return centerX + fraction * roadNearHalfWidth * scaleForZ(z);
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    road = Road();
    obstacleManager = ObstacleManager();
    coinManager = CoinManager();
    chaser = Chaser();
    player = Player();

    // Player must load (and set its initial position) before Chaser, since
    // Chaser.reset() reads the player's position to place itself.
    await addAll([road, obstacleManager, coinManager, player, chaser]);

    bestDistanceNotifier.value = await scoreManager.loadBest();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (state == GameState.running) {
      if (gameSpeed < maxGameSpeed) {
        gameSpeed = (gameSpeed + speedRampPerSecond * dt).clamp(
          initialGameSpeed,
          maxGameSpeed,
        );
      }
      _distanceAccumulator += gameSpeed * dt / 10;
      distanceNotifier.value = _distanceAccumulator.floor();
    }
  }

  /// Starts a fresh run, or resumes one that was paused.
  void start() {
    switch (state) {
      case GameState.ready:
        _resetEntities();
        state = GameState.running;
        audioManager.playBackgroundMusic();
        break;
      case GameState.paused:
        state = GameState.running;
        audioManager.resumeBackgroundMusic();
        break;
      case GameState.running:
      case GameState.gameOver:
        break;
    }
  }

  /// Pauses an in-progress run; [start] resumes it.
  void stop() {
    if (state != GameState.running) return;
    state = GameState.paused;
    audioManager.pauseBackgroundMusic();
  }

  /// Resets everything and begins a brand-new run after game over.
  void restart() {
    _resetEntities();
    state = GameState.running;
    audioManager.playBackgroundMusic();
  }

  void _resetEntities() {
    gameSpeed = initialGameSpeed;
    _distanceAccumulator = 0;
    distanceNotifier.value = 0;
    coinsNotifier.value = 0;
    obstacleManager.reset();
    coinManager.reset();
    player.reset();
    chaser.reset();
  }

  /// Called by [Coin] when the player runs through it.
  void onCoinCollected() {
    coinsNotifier.value++;
  }

  /// Called by [Player] when it collides with an [Obstacle].
  void onPlayerHitObstacle() {
    if (state != GameState.running) return;
    state = GameState.gameOver;
    audioManager.stopBackgroundMusic();
    chaser.startCatchUp();

    final distance = distanceNotifier.value;
    if (distance > bestDistanceNotifier.value) {
      bestDistanceNotifier.value = distance;
      scoreManager.saveBest(distance);
    }
  }

  /// Called by [Chaser] once it finishes closing the gap after a collision.
  /// Gameplay has already stopped by this point; this is purely a hook for
  /// any future catch-animation follow-up.
  void onChaserCaughtPlayer() {}

  /// Safe entry points for UI-driven input (swipes, buttons): no-ops until
  /// [onLoad] has finished building the component tree.
  void moveLeft() {
    if (isLoaded) player.moveLeft();
  }

  void moveRight() {
    if (isLoaded) player.moveRight();
  }

  void jump() {
    if (isLoaded) player.jump();
  }

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        player.moveLeft();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        player.moveRight();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
          event.logicalKey == LogicalKeyboardKey.space) {
        player.jump();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }
}
