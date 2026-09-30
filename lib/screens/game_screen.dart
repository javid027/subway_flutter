import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../game/game_state.dart';
import '../game/runner_game.dart';

/// Hosts the Flame [RunnerGame] and layers the minimal Flutter UI
/// (start / HUD / game-over panels) on top of it.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final RunnerGame _game;

  /// Minimum total finger travel (in logical pixels) before a pan counts as
  /// a deliberate swipe rather than tap jitter. Distance-gating (instead of
  /// a velocity-only check) is what stops a simple tap — e.g. on the Stop
  /// button — from ever being misread as a swipe.
  static const double _swipeDistanceThreshold = 28;

  Offset _panDelta = Offset.zero;

  @override
  void initState() {
    super.initState();
    _game = RunnerGame();
  }

  void _onPanStart(DragStartDetails details) {
    _panDelta = Offset.zero;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _panDelta += details.delta;
  }

  void _onPanEnd(DragEndDetails details) {
    final dx = _panDelta.dx;
    final dy = _panDelta.dy;
    // Reset immediately so no leftover delta can ever leak into the next
    // gesture, even if a future onPanStart is ever missed or delayed.
    _panDelta = Offset.zero;
    // Whichever axis moved further decides the gesture, so a swipe doesn't
    // need to be perfectly axis-aligned to register.
    if (dx.abs() >= dy.abs()) {
      if (dx.abs() < _swipeDistanceThreshold) return;
      if (dx < 0) {
        _game.moveLeft();
      } else {
        _game.moveRight();
      }
    } else {
      if (dy.abs() < _swipeDistanceThreshold) return;
      if (dy < 0) {
        _game.jump();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            // The swipe detector only wraps the game view, not the overlay
            // UI below, so taps on Start/Stop/Restart are never also read
            // as a swipe by an ancestor gesture recognizer.
            Positioned.fill(
              child: GestureDetector(
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                child: GameWidget(game: _game),
              ),
            ),
            ValueListenableBuilder<GameState>(
              valueListenable: _game.stateNotifier,
              builder: (context, state, _) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween(begin: 0.94, end: 1.0).animate(animation),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey(state),
                  child: _buildOverlay(state),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlay(GameState state) {
    switch (state) {
      case GameState.ready:
        return _ReadyPanel(game: _game);
      case GameState.running:
      case GameState.paused:
        return _Hud(game: _game, paused: state == GameState.paused);
      case GameState.gameOver:
        return _GameOverPanel(game: _game);
    }
  }
}

/// Shared palette so every panel/button reads as one consistent app theme.
class AppColors {
  AppColors._();

  static const background = Color(0xFF14141C);
  static const surface = Color(0xFF1E1E2C);
  static const surfaceBorder = Color(0x1FFFFFFF);
  static const accent = Color(0xFFFFA726);
  static const accentDark = Color(0xFFF57C00);
  static const danger = Color(0xFFFF5252);
  static const dangerDark = Color(0xFFD32F2F);
  static const gold = Color(0xFFFFD54F);
  static const textPrimary = Colors.white;
  static const textSecondary = Color(0xFFB0B0C0);
}

TextStyle _display(double size, {Color color = AppColors.textPrimary, double? letterSpacing}) {
  return GoogleFonts.poppins(
    fontSize: size,
    fontWeight: FontWeight.w700,
    color: color,
    letterSpacing: letterSpacing,
  );
}

TextStyle _body(double size, {Color color = AppColors.textSecondary, FontWeight weight = FontWeight.w500}) {
  return GoogleFonts.poppins(fontSize: size, fontWeight: weight, color: color);
}

/// A translucent, rounded card used for every panel in the app.
class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child, this.borderColor});

  final Widget child;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: borderColor ?? AppColors.surfaceBorder, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// A rounded, gradient-filled call-to-action button with an icon and label.
class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.colors,
    this.large = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final List<Color> colors;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: large ? 44 : 30,
            vertical: large ? 20 : 14,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: colors.last.withValues(alpha: 0.45),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: large ? 26 : 20),
              const SizedBox(width: 10),
              Text(
                label,
                style: _display(large ? 20 : 16, letterSpacing: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A circular icon-only button used for the in-run pause/resume control.
class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onPressed,
    required this.colors,
    this.diameter = 64,
    this.iconSize = 30,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final List<Color> colors;
  final double diameter;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: colors),
            boxShadow: [
              BoxShadow(
                color: colors.last.withValues(alpha: 0.5),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: iconSize),
        ),
      ),
    );
  }
}

/// A small translucent pill used to show a stat (distance, best) with icon.
class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label, this.iconColor = AppColors.accent});

  final IconData icon;
  final String label;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.surfaceBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 8),
          Text(label, style: _display(16)),
        ],
      ),
    );
  }
}

/// The in-run heads-up display: a small pause/resume control top-left,
/// the distance counter beside it, and a coin counter top-right —
/// following the layout conventions common to this genre (corner pause,
/// running total near it, currency count opposite) without reproducing
/// any specific game's exact iconography.
class _Hud extends StatelessWidget {
  const _Hud({required this.game, required this.paused});

  final RunnerGame game;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: 16,
          left: 16,
          child: _CircleIconButton(
            icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            onPressed: paused ? game.start : game.stop,
            diameter: 44,
            iconSize: 22,
            colors: paused
                ? [AppColors.accent, AppColors.accentDark]
                : [AppColors.danger, AppColors.dangerDark],
          ),
        ),
        Positioned(
          top: 22,
          left: 70,
          child: ValueListenableBuilder<int>(
            valueListenable: game.distanceNotifier,
            builder: (context, distance, _) => _StatChip(
              icon: Icons.directions_run_rounded,
              label: '$distance m',
            ),
          ),
        ),
        Positioned(
          top: 22,
          right: 16,
          child: ValueListenableBuilder<int>(
            valueListenable: game.coinsNotifier,
            builder: (context, coins, _) => _StatChip(
              icon: Icons.monetization_on_rounded,
              label: '$coins',
              iconColor: AppColors.gold,
            ),
          ),
        ),
        if (paused)
          Center(
            child: _GlassCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.pause_circle_filled_rounded, color: AppColors.accent, size: 40),
                  const SizedBox(height: 8),
                  Text('PAUSED', style: _display(22, letterSpacing: 1)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _GameOverPanel extends StatelessWidget {
  const _GameOverPanel({required this.game});

  final RunnerGame game;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _GlassCard(
        borderColor: AppColors.danger.withValues(alpha: 0.35),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sentiment_dissatisfied_rounded, color: AppColors.danger, size: 44),
            const SizedBox(height: 8),
            Text('GAME OVER', style: _display(28, color: AppColors.danger, letterSpacing: 1)),
            const SizedBox(height: 18),
            ValueListenableBuilder<int>(
              valueListenable: game.distanceNotifier,
              builder: (context, distance, _) => ValueListenableBuilder<int>(
                valueListenable: game.bestDistanceNotifier,
                builder: (context, best, _) {
                  final isNewBest = distance > 0 && distance == best;
                  return Column(
                    children: [
                      Text('$distance m', style: _display(36)),
                      const SizedBox(height: 10),
                      if (isNewBest)
                        _StatChip(
                          icon: Icons.emoji_events_rounded,
                          label: 'NEW BEST!',
                          iconColor: AppColors.gold,
                        )
                      else
                        _StatChip(
                          icon: Icons.emoji_events_rounded,
                          label: 'Best: $best m',
                          iconColor: AppColors.gold,
                        ),
                      const SizedBox(height: 10),
                      ValueListenableBuilder<int>(
                        valueListenable: game.coinsNotifier,
                        builder: (context, coins, _) => _StatChip(
                          icon: Icons.monetization_on_rounded,
                          label: '$coins collected',
                          iconColor: AppColors.gold,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 26),
            _GradientButton(
              label: 'RESTART',
              icon: Icons.replay_rounded,
              onPressed: game.restart,
              colors: const [AppColors.accent, AppColors.accentDark],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadyPanel extends StatelessWidget {
  const _ReadyPanel({required this.game});

  final RunnerGame game;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _GlassCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [AppColors.accent, AppColors.accentDark]),
              ),
              child: const Icon(Icons.directions_run_rounded, color: Colors.white, size: 40),
            ),
            const SizedBox(height: 18),
            Text('MINIMAL RUNNER', style: _display(26, letterSpacing: 1)),
            const SizedBox(height: 6),
            Text('Dash. Dodge. Survive.', style: _body(14)),
            const SizedBox(height: 16),
            ValueListenableBuilder<int>(
              valueListenable: game.bestDistanceNotifier,
              builder: (context, best, _) => best > 0
                  ? _StatChip(
                      icon: Icons.emoji_events_rounded,
                      label: 'Best: $best m',
                      iconColor: AppColors.gold,
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 24),
            _GradientButton(
              label: 'START',
              icon: Icons.play_arrow_rounded,
              onPressed: game.start,
              colors: const [AppColors.accent, AppColors.accentDark],
              large: true,
            ),
            const SizedBox(height: 22),
            _ControlsHint(),
          ],
        ),
      ),
    );
  }
}

class _ControlsHint extends StatelessWidget {
  const _ControlsHint();

  @override
  Widget build(BuildContext context) {
    Widget hint(IconData icon, String label) => Column(
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 20),
            const SizedBox(height: 4),
            Text(label, style: _body(11)),
          ],
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        hint(Icons.swipe_left_alt_rounded, 'Swipe'),
        const SizedBox(width: 22),
        hint(Icons.swipe_up_alt_rounded, 'Jump'),
        const SizedBox(width: 22),
        hint(Icons.swipe_right_alt_rounded, 'Swipe'),
      ],
    );
  }
}
