/// The high-level phases the runner game can be in.
enum GameState {
  /// Nothing has started yet; the "start" overlay is shown.
  ready,

  /// The game loop is active: player, obstacles and chaser are all moving.
  running,

  /// Gameplay is paused (via the Stop button) and can be resumed.
  paused,

  /// The player was caught; the "game over" overlay is shown.
  gameOver,
}
