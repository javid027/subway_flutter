import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the player's best distance across app launches. Kept as its own
/// system (like [AudioManager]) so `RunnerGame` doesn't talk to
/// SharedPreferences directly.
///
/// Every call is defensive: if the platform's storage plugin isn't
/// available for any reason, this falls back to an in-memory best for the
/// current session instead of ever blocking game start-up.
class ScoreManager {
  static const String _bestDistanceKey = 'best_distance';

  int _sessionBest = 0;

  Future<int> loadBest() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _sessionBest = prefs.getInt(_bestDistanceKey) ?? 0;
    } catch (e) {
      debugPrint('ScoreManager: could not load best distance: $e');
    }
    return _sessionBest;
  }

  Future<void> saveBest(int distance) async {
    _sessionBest = distance;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_bestDistanceKey, distance);
    } catch (e) {
      debugPrint('ScoreManager: could not save best distance: $e');
    }
  }
}
