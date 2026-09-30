# Background music

Place a royalty-free/local soundtrack file here named:

```
background_music.mp3
```

so the full path is `assets/audio/background_music.mp3`.

The game (`lib/game/systems/audio_manager.dart`) loads exactly this filename
through `flame_audio`'s `FlameAudio.bgm`, which loops it automatically while
the game is running. If the file is missing, `AudioManager` catches the load
error and the game continues silently (no crash) — you'll just have no music
until the file is added.

Do not use copyrighted Subway Surfers music; use a track you have the rights
to (e.g. from a royalty-free library such as freesound.org, Pixabay Music, or
your own composition).

After adding the file, run:

```
flutter pub get
```

and restart the app (a hot reload is not enough for newly added assets).
