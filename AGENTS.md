# AGENTS.md — copy_cat (Mimic Party)

Offline, local-LAN **voice mimic party game** (host/join over the same network, no internet).

## Stack

- Flutter, Dart SDK ^3.13.2. Lints: `flutter_lints` (see `analysis_options.yaml`).
- **State: Riverpod 3** (`flutter_riverpod` ^3.4.3). Prefer Riverpod providers over
  hoisting mutable state into widgets.
- **Navigation: go_router ^18** (`lib/app_router.dart`). Named `GoRoute`s; the `_BackTo`
  wrapper redirects system back to a specific route — preserve it when adding screens.
- **3D: flutter_scene ^0.24.0.** Generated per-platform shader/asset bundles live in
  `flutter_scene_generated/` (declared in `pubspec.yaml`). Use the flutter_scene skills;
  this engine is *not* three.js/Unity.

## Layout

```
lib/
  models/      # data types (game_sound, player)
  screens/     # one file per screen (splash, home, lobby, gameplay, results, shop, ...)
  services/    # audio, LAN, scoring, catalogs — no widget code here
  state/       # Riverpod engines/stores (host_engine, client_engine, game_state, coins, shop_store)
  widgets/     # shared reusable widgets
  app_router.dart, main.dart
```

Networking: `bonsoir` ^7 for LAN discovery + `services/lan_socket_manager.dart` for
host↔client traffic. **The app must work with no internet connection at runtime** —
the dev machine, however, IS online (pub.dev and npm are reachable).

## Hard rules

- **Ask before adding pub dependencies.** Several PLAN-listed packages were
  intentionally replaced with framework/native APIs in the past (reasons documented
  in `pubspec.yaml` comments) — read those comments before suggesting any new
  package, and keep the runtime-offline requirement in mind when evaluating deps.
- Audio playback goes through `services/native_audio.dart` (platform channels), not
  just_audio/file_picker. Pitch extraction is hand-rolled in
  `services/pitch_extractor.dart` (RMS + zero-crossing) — no pitch package exists that
  matches the plan.
- Scoring logic follows `mimic_scoring_spec.md`; implementations are
  `services/audio_scorer.dart` + `services/attempt_scorer.dart`, with regression tests
  (`test/gemini_scoring_test.dart`, `test/audio_scorer_test.dart`). Change both together.

## Verify changes

- `flutter analyze` — must be clean.
- `flutter test` — scoring/sound tests are the sensitive ones.
