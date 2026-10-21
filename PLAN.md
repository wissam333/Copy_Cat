# Mimic Party — what to build next

OpenCode: read this file and implement it. Do not treat the three game modes as one phone passed around the room. That was the last mistake.

There are two ways to play:

1. **Solo phone.** One device. Already exists (`/party` → `/game`). Leave this path working.
2. **LAN room.** Each player is on their own phone, same Wi-Fi or hotspot, up to 5 phones. **Random, Choice, and Host exist only here.**

The host phone is the referee. Clients do not start their own match.

---

## Do not undo

These already work. Do not replace them.

- `AudioScorer` in `lib/services/audio_scorer.dart`. Score is 0–100. Silence is 0. An identical contour is 100. The melody score is the **shape** of the tune (median-centered semitones, so a different key still scores high) plus rhythm from the loudness envelope. Unpitched clips (claps, laughs) score on rhythm only. Keep `calculateScore` and `judge`.
- WAV pitch + energy extraction in `lib/services/pitch_extractor.dart`.
- Import path that decodes m4a/mp3 to WAV in `SoundLibraryService.ingest` and `MainActivity.transcodeToWav`, so the stored `pitchMap` is real.
- Library rule: only sounds from **3.0 to 6.0 seconds**.
- Socket framing already in `lib/services/lan_socket_manager.dart`: `[4 byte big-endian length][1 byte type][payload]`. Types `0x01`–`0x06` stay. You may add types. Do not invent a second protocol.
- Room discovery (`bonsoir`, type `_mimicparty._tcp`, port `8080`) and manual IP join (`192.168.43.1`).
- Room lock: after Start, `isRoomLocked` rejects new sockets.

---

## What is wrong today

`HomeScreen` sends Random / Choice / Host to `/party`, which adds fake local players and plays every turn on one phone.

`LobbyScreen` Start only broadcasts `{locked: true}` and each phone opens `/game` and runs `startRandomMatch` on **its own** library. Phones do not share one sound, one turn order, or one scoreboard.

Fix that. Solo stays on `/party`. The three modes start only from the host lobby.

---

## Home

`lib/screens/home_screen.dart`

- One button: **لعب لحالي** → `/party`. This is the solo phone. Do not show the three LAN modes here.
- **إنشاء غرفة** → `/lobby?host=1`
- **انضمام** → `/lobby?host=0`
- **أصواتي** → `/library`

Arabic UI, RTL, keep the current look.

---

## Solo phone (do not expand)

`PartySetupScreen` + the local branch of `GameplayScreen`.

- One phone, one or more names, pass the phone.
- It is practice / a couch game. It is **not** Random, Choice, or Host.
- Do not require LAN. Do not sync files.
- Keep listen once → 5 s countdown → auto-record → `AudioScorer` → points add up.

---

## LAN room

### Who is who

- Host creates the room and is player 0. Host `isHost == true`.
- Each joining phone sends its name once and becomes the next player. One phone = one player. Max 5. Ignore extra joins.
- Order is join order. Do not add “pass the phone” players inside a LAN room.
- Clients show the same player list, mode, and lock state as the host.

### Lobby — `lib/screens/lobby_screen.dart`

Host only:

- Three mode cards, with these exact meanings (see flows below): **حفلة عشوائية**, **اختيار اللاعب**, **تحدي المضيف**.
- Player list from **connected phones**, not typed names.
- **ابدأ اللعب** is enabled only when at least 2 phones are in the room (host + one friend). One phone uses Solo instead.
- Start locks the room, tells every client the mode, and the **host** begins the match state machine. Clients navigate to `/game` and **wait**. They must not call `startRandomMatch` / `startChoiceMatch` / `startHostMatch` on their own library.

Client lobby:

- No mode picker. Show the mode the host picked.
- No Start button.
- Can leave.

### Packets

Keep `0x01`–`0x06`. Put JSON in the payload unless the type is raw audio.

| Type | Name | Who | Payload |
|---|---|---|---|
| `0x01` | Lobby | host → all, and client → host for join | `{players, mode, locked, youAre}` |
| `0x02` | Sound manifest | host → all | `{soundId, title, durationSeconds, pitchMap, fileSize, roundIndex}` |
| `0x03` | Sound bytes | owner → host, host → all | raw file bytes for the `soundId` announced in the last `0x02` |
| `0x04` | Turn start | host → all | `{playerId, soundId, roundIndex, turnInRound}` |
| `0x05` | Score | active phone → host, host → all | `{playerId, soundId, roundIndex, score, melody, rhythm, pitched}` |
| `0x06` | Timeout | host → all | `{playerId, roundIndex, score: 0}` |
| `0x07` | Library offer | each client → host, once when the match is about to start | `{playerId, sounds: [{id, title, durationSeconds, pitchMap, fileSize}]}` |
| `0x08` | Pick | host → selector, then selector → host | host: `{roundIndex, selectorId}`. selector: `{soundId}` then `0x02`+`0x03` of that file |
| `0x09` | Phase | host → all | `{stage, roundIndex, roundsTotal, selectorId, activePlayerId, soundTitle, scoreboard}` so idle phones can show the right screen |
| `0x0A` | Match over | host → all | `{scoreboard, attempts}` then every phone opens results |

`scoreboard` is a map of `playerId → total points` (sum of round scores, not the last score only).

Sound bytes: send the whole file in one `0x03` frame (clips are a few seconds). Host writes it to a temp file and builds a `GameSound` whose `pitchMap` is the one from `0x02`. Do not invent a contour. If `pitchMap` is empty, extract it from the WAV on the receiving phone.

### Turn script (every mode, active phone only)

When `0x04` says `playerId` is **this** phone:

1. Play the synced challenge **once**. No replay button.
2. 5-second countdown. No tap to skip.
3. Record for the challenge duration, clamped to 3–6 s.
4. Score locally with `AudioScorer.judge` (pitch + energy of the challenge file and the attempt).
5. Send `0x05` to the host. Do not wait for a confirm button.

Other phones, same moment: show **دور {name}** and the sound title. Do not play the clip. Do not open the mic.

### Timeout

The old “15 seconds from the start of the turn” is wrong. Listen + 5 s + record is already longer than 15 s, so a real mimic was scored 0.

The host starts a watchdog when it sends `0x04`:

`durationSeconds * 2 + 5 + 20` seconds.

If `0x05` arrives first, cancel it. If it fires, that player gets 0 for this turn, tell the room with `0x06`, and advance. Do not also apply a late score for that same turn (first result wins).

### After each attempt

Host adds the score to that player’s total, broadcasts `0x09` (and the score). When every player in this round has a result, either start the next turn of this sound or finish the round. When the match ends, send `0x0A`. Every phone shows the same leaderboard and can play the best attempt **if** the attempt file was included; if you do not ship attempt audio, hide “play winning attempt” instead of playing the wrong file. Shipping attempt audio is optional. Scores are not.

---

## Mode 1 — Random (LAN)

Host picks the sounds. Players only mimic.

1. On Start, host asks every client for `0x07` (their library metadata, no files yet). Host includes its own library. Wait up to 3 s, then play with whatever arrived.
2. Pool = those sounds. Shuffle. Take up to **5** distinct sounds. That is the round count. If the pool is empty, stay in the lobby and say **ما في أصوات — كل واحد يضيف صوت 3–6 ثوانٍ**.
3. For each sound, in order:
   - Host requests `0x03` from the phone that owns it (or reads the file locally if the host owns it).
   - Host broadcasts `0x02` then `0x03` to everyone, including itself.
   - Turns: player 0, then 1, … then last. **Same sound.**
4. Then the next sound. Then `0x0A`.

Nobody picks during the round. The surprise is the point.

---

## Mode 2 — Choice (LAN)

One phone chooses. The others mimic first. The chooser goes last. Then the next phone chooses.

1. Rounds = number of players. Each player selects **once**. Selector starts at player 0, then +1 each round.
2. Host sends `0x08` to the selector only, and `0x09` to everyone: **{name} يختار الصوت**.
3. Selector’s phone shows **their** library. They may preview. Others do not hear that preview. Confirm sends `0x08` with `soundId`, then `0x02` + `0x03` to the host.
4. Host forwards `0x02` + `0x03` to the whole room.
5. Turn order: every player **except** the selector, in join order, then the selector last.
6. Next round, next selector. After the last selector’s round, `0x0A`.

If the selector never picks within 30 s, host skips to the next selector and that round is dropped (or host assigns 0 to the selector and continues — pick **skip the round**, do not stall the room).

---

## Mode 3 — Host (LAN)

The room host picks the playlist **before** Start, from the **host library only**.

1. In the host lobby, when this mode is selected, show the host’s sounds. Tap to build an ordered queue, 1 to 5. Start stays disabled until the queue has at least 1 sound and at least 2 phones.
2. On Start, do not ask clients for libraries.
3. For each queued sound: host broadcasts `0x02` + `0x03`, then every player attempts in join order (host included), same automated turn script.
4. Next sound. Then `0x0A`.

Clients never see a picker in this mode.

---

## Gameplay screen

`lib/screens/gameplay_screen.dart`

Split the screen on “am I in a LAN match?”:

- **Solo:** keep the current local flow.
- **LAN:** render from host `0x09` / `0x04` only.
  - Waiting: sound title, whose turn, round `2 / 5`, running totals.
  - My turn: the existing listen / countdown / record / score reveal.
  - Someone else’s turn: their name, no audio, no mic.
  - Choice, and I am the selector: the sound picker, then the file upload.
  - Reveal: show **my** last score when `0x05` echoes back, with the rank label already in `scoreLabel`. Totals come from the host scoreboard, not from a local `completeTurn` that also advances the round.
- Leaving the screen does not unlock the room. Back asks “تبي تطلع؟” and then disconnects that phone. Host leaving ends the match (`0x0A` with whatever scores exist).

The host’s game controller advances rounds. A client must not call `nextAfterReveal` to change the global turn.

---

## Results

`lib/screens/results_screen.dart`

- LAN and solo can share the layout.
- LAN results come from `0x0A`. Rank by total points. Show each round’s 0–100 scores under it.
- **نفس الحفلة** on the host starts the same mode again (Choice and Random reshuffle / re-pick; Host mode reuses the same queue). Clients wait for the host. Do not let a client start the next match.

---

## Files to touch

- `lib/screens/home_screen.dart` — solo vs room entries.
- `lib/screens/lobby_screen.dart` — mode cards, real player list, host playlist, start rules.
- `lib/screens/gameplay_screen.dart` — LAN wait / my turn / their turn / selector.
- `lib/state/game_state.dart` — host match state: mode, order, round, totals. Do not let clients overwrite it with a local `startRandomMatch`.
- `lib/services/lan_socket_manager.dart` — new packet types only if you cannot fit the JSON above into the existing send/broadcast helpers. Framing stays.
- `lib/screens/results_screen.dart` — host-driven totals.
- `lib/screens/party_setup_screen.dart` — solo only. Remove any copy that says the three modes are this screen.

Do not add Firebase, accounts, or an internet server. LAN only.

---

## Done when

1. Two phones on one Wi-Fi: host creates, friend joins from the discovered room **or** by typing the host IP, both see both names.
2. A third connection after Start is dropped.
3. **Random:** both phones mimic the **same** clip, one after the other, on their **own** mics. A second round is a **different** clip if the pool has one. Scoreboards match.
4. **Choice:** phone A picks; phone B mimics first; phone A mimics last. Next round phone B picks.
5. **Host:** only the host’s queue plays, in that order, both phones each turn.
6. A phone that is not the active player stays silent (no speaker, no mic).
7. Solo **لعب لحالي** still runs with no network.
8. `flutter test` still passes, including identical contour = 100, silence = 0, transposed melody still high.
