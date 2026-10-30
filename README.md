# 🎭 Mimic Party

**An offline, local-LAN voice mimic party game.** Record a sound — a scream, a
beep, claps, whatever plays out of the phone — then watch every friend try to
imitate it while a merciless on-device judge grades them. No internet, no
accounts, no servers. One Wi-Fi or even just a hotspot, up to 5 phones.

![Release](https://img.shields.io/github/v/release/wissam333/Copy_Cat)
![Platform](https://img.shields.io/badge/platform-Android%20(phone%20first)-3ddc84)
![Runtime](https://img.shields.io/badge/runtime-offline%20(LAN%20only)-blue)

> واجهة اللعبة بالعربية بالكامل (RTL) — catch jokes, taunt with emoji, steal
> the crown. Everything else in this README is in English for the code side.

**Try the judge in your browser** 🎤 — [live demo page](https://wissam333.github.io/Copy_Cat/)
(record or upload two clips and see the exact four-axis verdict; runs entirely
client-side, no audio leaves the page). The demo is a TypeScript port of the
same scoring math, kept honest by parity tests against the Dart judge
(`demo/test/parity.test.ts`). Source under [`demo/`](demo/).

---

## Get it — no build needed

Download the latest APK from
[**Releases**](https://github.com/wissam333/Copy_Cat/releases) and install it
on any Android phone. That's the whole ceremony:

- Releases are signed with a **fixed key**, so the next version installs
  straight over the old one — no uninstalling, your coins and sounds stay.
- First launch follows your phone's language; the **عربي / EN** pill on the
  home screen overrides it anytime.
- The app never touches the internet at runtime. Turn on airplane mode and
  host a hotspot if you want to feel the point.

---

## How it plays

1. **Host a room** — the host phone's Wi-Fi becomes the referee.
2. **Everyone joins** on the same network (auto-discovery, or by IP).
3. Someone's turn: the phone plays the sound **once**, waits 3 seconds, then
   records your take automatically — while it records you see the original's
   waveform in blue with **your live voice drawn over it in orange**, in real
   time. Try to shadow the shape, not just the sound.
4. The reveal: you get four colored bars per axis — melody, rhythm, timbre,
   energy — colored by strength (🔴 amber 🟢), a big grade with a dramatic
   countdown, the two waveforms overlaid for the post-mortem, and the joke
   the judge generated about your attempt.
5. Coins → shop → 3D characters, pay-per-send emoji taunts, and match
   power-ups.

Two play styles:

| Mode | Behind it |
|---|---|
| **Party (couch)** | One phone, pass it around. Up to 5 players on the same device. Great as a mic-training warm-up. |
| **LAN room** | Each player has their own phone. Random, Choice, and Host challenge modes live here only. The host phone runs the whole match: order, sounds, scores, power-up legality. |

---

## Two languages, one dictionary

The UI is Arabic-first with a complete English translation behind a single
pill on the home screen. No `.arb` files, no codegen: the Arabic string *is*
the key, and `i18n.dart` holds one English map — anything untranslated simply
passes through as the Arabic original.

- First run follows the phone's language; your pick is remembered.
- In a LAN room, joke text follows the **host's** language — one referee
  voice per room.
- A coverage test fails the build if any Arabic string in `lib/` lacks an
  English entry, so English mode can never leak bare Arabic.

---

## The judge — honest scoring in one minute

Scoring is not "vibes". It is a documented four-axis score per take
(`mimic_scoring_spec.md` is the source of truth; a regression suite guards it,
and the scoring/sound tests are the sensitive ones):

| Axis | What it grades |
|---|---|
| **اللحن (melody)** | Shape of your pitch contour, median-centered — sing it in another key and it still counts |
| **الإيقاع (rhythm)** | When you made noise vs when the original did (loudness envelope alignment) |
| **النبرة (timbre)** | MFCC texture — is your "voice" even the same animal as the clip |
| **الطاقة (energy)** | Loud shifts: were you bold or did you whisper |

And it is *clip-class aware*: the judge listens to the target first.

- 🎼 **Sung clips** → melody + rhythm 30/30, timbre/energy 20/20
- 🗣️ **Spoken clips** → clarity (timbre) 35, rhythm 25, energy/melody 20
- 👏 **Claps/laughs (no pitch)** → timbre 40 / rhythm 25 / energy 35 — melody
  is not even shown in the reveal; claps are graded as claps

Anti-cheat guards, all on-device: silence scores 0 (amplified room tone fails
too), a held "aaaa" against a moving tune is penalized, one thump is never
four claps, and any load-bearing axis that fails badly caps the whole take —
you cannot ride loudness or good timing past a melody you ignored.

---

## Power-ups (host-enforced, bought with coins)

| Power | Emoji | Effect |
|---|---|---|
| مضاعفة ×2 | ✖️ | Arms **before your take** — doubles the recorded points. It can never rewrite a grade you already saw. |
| درع | 🛡️ | Drops your worst round from the final total at match end. |
| برق | ⚡ | (Waiting players) forces the active player to redo their turn exactly once. |

Uses are consumed on send; the host validates timing, so no refunds for
creative mistiming.

## Library — where the ammo lives

Every sound is a local file: import **m4a/mp3/whatever**, it transcodes to
WAV on-device (Android platform channel, no third-party codec dependency),
and the preview paints the **pitch contour over the waveform** so you can see
what you are about to order everyone to imitate. Clips are 2–6 seconds by
rule — long audios are rejected, not pitied.

---

## Build it

```bash
flutter pub get
flutter analyze        # must be clean in lib/
flutter test           # scoring/shop regressions are the sensitive ones
flutter run            # pick a device
```

- **Dev machine needs internet** once (pub + build mirrors); **the app itself
  never does** at runtime — LAN only.
- Android-first (tested on release builds). Recommended for real play:
  `flutter build apk --release`.
- On networks where Google's Maven endpoints are filtered, this repo ships
  mirror-first Gradle configs (Huawei/Aliyun) with the official endpoints as
  fallback — see `android/build.gradle.kts`.

## The code, in one breath

```
lib/
  models/     # game_sound, player
  screens/    # splash, home, lobby, gameplay, results, shop, library, ...
  services/   # audio_io, native_audio (platform channels), pitch_extractor,
              # audio_scorer + attempt_scorer (the judge), lan_socket_manager,
              # shop_catalog, instant_sounds
  state/      # Riverpod: host_engine (referee), client_engine, game_data,
              # coins, shop_store
  widgets/    # reveal meters, 3D avatars (flutter_scene), waves, UI bits
```

- **Flutter + Dart ^3.13**, **Riverpod 3** for state, **go_router** for nav.
- **flutter_scene** renders the 3D avatars and the celebration on results.
- **bonsoir** mDNS (`_mimicparty._tcp`) finds rooms; host↔client traffic runs
  through a tiny custom binary protocol:
  `[4-byte length][1-byte type][payload]` — types 0x01…0x0C, each small and
  boring on purpose.
- Pitch extraction is **hand-rolled YIN** (50 ms windows, RMS silence gate,
  median smoothing) — no store-bought pitch package claims this game's judge.
- Solo and LAN turns run through the *same* turn runner and the *same*
  scorer, so the same two files can never produce two different grades.

## Where it's going

Deferred backlog (see `PLAN.md`): attempt-audio "bloopers" reel shared at
match end, per-player mimic profiles with personal bests, elimination mode.

---

*A party game about how badly your friends imitate a refrigerator hum.*
