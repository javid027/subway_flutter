import 'dart:math';

import 'package:flame/components.dart';

import '../components/obstacle.dart';
import '../game_state.dart';
import '../runner_game.dart';

/// Owns obstacle spawning: picks a random lane on a randomized timer and
/// adds a new [Obstacle] above the visible screen. The spawn interval
/// tightens as [RunnerGame.gameSpeed] ramps up, so obstacles come more
/// frequently the longer a run goes — floored so it never becomes unfair.
class ObstacleManager extends Component with HasGameReference<RunnerGame> {
  ObstacleManager({this.minInterval = 0.9, this.maxInterval = 1.6});

  final double minInterval;
  final double maxInterval;

  /// Never spawn faster than this, regardless of how fast the game gets.
  static const double floorInterval = 0.45;

  final Random _random = Random();
  double _timeUntilNextSpawn = 0;
  int? _lastLane;

  /// Clears any obstacles still on screen and resets the spawn timer.
  void reset() {
    _timeUntilNextSpawn = minInterval;
    _lastLane = null;
    for (final obstacle in game.descendants().whereType<Obstacle>().toList()) {
      obstacle.removeFromParent();
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (game.state != GameState.running) return;

    _timeUntilNextSpawn -= dt;
    if (_timeUntilNextSpawn <= 0) {
      _spawnObstacle();
      final speedFactor = game.gameSpeed / RunnerGame.initialGameSpeed;
      final effectiveMin = max(floorInterval, minInterval / speedFactor);
      final effectiveMax = max(floorInterval * 1.4, maxInterval / speedFactor);
      _timeUntilNextSpawn =
          effectiveMin + _random.nextDouble() * (effectiveMax - effectiveMin);
    }
  }

  void _spawnObstacle() {
    var lane = _random.nextInt(RunnerGame.laneCount);
    if (lane == _lastLane) {
      lane = (lane + 1 + _random.nextInt(RunnerGame.laneCount - 1)) %
          RunnerGame.laneCount;
    }
    _lastLane = lane;
    game.add(Obstacle(laneIndex: lane));
  }
}
