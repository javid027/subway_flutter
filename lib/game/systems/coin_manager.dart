import 'dart:math';

import 'package:flame/components.dart';

import '../components/coin.dart';
import '../game_state.dart';
import '../runner_game.dart';

/// Spawns short coin trails (a handful of coins strung along one lane) on
/// a randomized timer, independently of [ObstacleManager]. Coins are a
/// bonus, not a hazard, so lane choice is simple random — no need to
/// coordinate with obstacle placement.
class CoinManager extends Component with HasGameReference<RunnerGame> {
  CoinManager({
    this.minInterval = 1.6,
    this.maxInterval = 2.6,
    this.trailLength = 4,
  });

  final double minInterval;
  final double maxInterval;
  final int trailLength;

  /// World-depth spacing between coins within one trail.
  static const double trailSpacing = 1.1;

  final Random _random = Random();
  double _timeUntilNextSpawn = 0;

  void reset() {
    _timeUntilNextSpawn = minInterval;
    for (final coin in game.descendants().whereType<Coin>().toList()) {
      coin.removeFromParent();
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (game.state != GameState.running) return;

    _timeUntilNextSpawn -= dt;
    if (_timeUntilNextSpawn <= 0) {
      _spawnTrail();
      _timeUntilNextSpawn =
          minInterval + _random.nextDouble() * (maxInterval - minInterval);
    }
  }

  void _spawnTrail() {
    final lane = _random.nextInt(RunnerGame.laneCount);
    for (var i = 0; i < trailLength; i++) {
      game.add(Coin(laneIndex: lane, startZ: Coin.spawnZ + i * trailSpacing));
    }
  }
}
