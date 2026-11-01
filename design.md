# Copy Cat — Stage Black UI

Visual spec for **both** ways to play. Another agent should be able to finish the restyle from this file alone. Solo and LAN each get a full UI pass. Do not spend the polish on one and leave the other as a recolor.

- **Solo** — `/party` → `/game?solo=1` → `/results` when no LAN match is active. One phone, passed around the room.
- **LAN** — home → `/lobby?host=1` (host) or `/lobby?host=0` (join) → `/game` with no `solo` flag → `/results` while `match.active`. Two or more phones on the same Wi‑Fi. The host runs the match. Joiners follow. Discovery, room lock, the three modes, the host sound queue, power-ups, and reactions are part of this screen set. They need the same clarity as the solo screens.

`GameplayScreen` has `_buildLan` and a solo branch. `ResultsScreen` has `_lanResults` and `_soloResults`. Design both branches. Keep every LAN-only control (power-ups, reactions, nearby rooms, manual IP, mode queue). Do not delete a LAN branch while editing the solo one.

Logic stays. Routes, providers, `onPressed` targets, and `t()` keys stay. What changes is hierarchy, spacing, type, color, empty states, and which button reads as the next step.

The art direction already exists as a throwaway preview in `lib/screens/design_mock_screen.dart` (long-press the home title, route `/design`). That file is **not** the product. Apply Stage Black to the real screens below. Do not leave the look trapped in the mock.

## Do not change

- Game, scoring, audio, LAN, shop, coin, or navigation **logic**.
- Routes in `lib/app_router.dart`, provider calls, button `onPressed` targets, or the `_BackTo` back-redirect wrapper.
- Copy keys passed to `t(...)`. Restyle widgets; do not rewrite strings. The app is Arabic-first and also English.
- `services/` and `state/` except colors that widgets already read from them (`scoreColor` may be retuned to the palette below; the thresholds in `scoreLabel` stay).
- Tests that assert scores. `flutter analyze` must stay clean. Run `flutter test` if a scoring color helper changes.
- Ask before adding a pub dependency. No new packages are required for this pass.
- Runtime stays offline. Fonts are already in `pubspec.yaml`: `ReemKufi` (display) and `PlexArabic` (UI, includes Latin).

## What “good” means here

Both modes are a party game used at arm’s length, often in Arabic (RTL). Solo passes one phone around. LAN puts one phone in each player’s hands on the same Wi‑Fi. One screen, one job. The next action is obvious, thumb-sized, and never hidden under a poster-sized title. Apply every rule below to solo and to LAN.

- One gold primary action per screen. Everything else is quieter.
- Every tappable control is at least 48px tall. Icon-only buttons need a tooltip.
- Say who, what, and what happens next. A score without a name, a sound title, and “/100” is not a score.
- Group related actions under a short label (“or on the same Wi‑Fi”) so two equal buttons do not fight the primary one.
- Selected state is obvious: gold border or gold radio, plus one sentence that changes with the selection.
- Empty, waiting, locked, and error states stay on the same screen. Do not swap in a blank purple page.
- Short phones must scroll. Pin the action that continues the game: start on `/party`, start on the host lobby, “next” on both reveals. Home shows both ways to play above the fold on a normal phone.
- Do not use 80–100px wordmarks. Display type is for the score and the splash title only.
- Flat `#000` is not the look. Page background is near-black with one soft gold radial glow behind the top of the screen.

## Palette

Put these on a single `ThemeData` used by `MaterialApp.router` in `lib/main.dart`. Screens should read `Theme` / `ColorScheme`, not invent new hex values.

| Token | Hex | Use |
| --- | --- | --- |
| bg | `#0A0A0F` | Scaffold, app bar |
| panel | `#14141B` | Cards, sheets, text fields |
| elev | `#1C1C26` | Chips, icon wells, selected segment |
| line | `#FFFFFF` at 12% | Card hairline |
| lineStrong | `#FFFFFF` at 24% | Buttons, pills, inputs |
| gold | `#E8B44C` | Primary, scores, active icon, links |
| onGold | `#14110A` | Text and icons on gold |
| text | `#F5F2EA` | Primary text |
| muted | `#A3A3B2` | Help, captions, footnotes |
| ok | `#3ECF8E` | Score ≥ 80, equipped, success |
| warn | `#E8B44C` | Score 50–79 (same gold; the bar still reads) |
| bad | `#E15D5D` | Score &lt; 50, mic / record, destructive |
| track | `#FFFFFF` at 12% | Meter and wave tracks |

Player avatars keep a stable color from `playerColor(id)` so people can tell each other apart. Those colors sit on a dark circle; the letter on them stays cream, not gold-on-gold.

Type:

- UI, buttons, body: `PlexArabic`. Weights 400 / 600 / 700 only.
- Wordmark, big score, countdown numeral: `ReemKufi`.
- Numbers that tick (score, coins, timer): `FontFeature.tabularFigures()`.
- Arabic body at 13–15px, line height about 1.35. No letter-spacing on Arabic.

Shape: cards 20, buttons 16, pills full pill, icons in 10px rounded squares. No drop shadows except a 2px shadow under the sprite play button (it is a physical button).

## Theme wiring

Create `lib/stage_theme.dart` and pass it as `theme:` from `MimicPartyApp`. One dark theme. Do not add a light/dark toggle to the shipped app (the mock’s toggle is preview-only).

`ColorScheme.dark` values:

- `primary` / `onPrimary` = gold / onGold
- `primaryContainer` / `onPrimaryContainer` = `#3A2E14` / gold (selected cards and chips)
- `surface` = panel, `surfaceContainerHighest` = elev
- `onSurface` = text, `onSurfaceVariant` = muted
- `error` = bad, `outline` = lineStrong

Component themes:

- App bar: bg, elevation 0, cream foreground, no purple.
- Cards: panel, elevation 0, 20px radius, 1px `line`.
- Filled buttons: gold fill, onGold label, height ≥ 52, 16px radius. Disabled: same shape, 40% opacity, not a grey Material default.
- Outlined / text buttons: transparent or panel, cream label, `lineStrong` border.
- Inputs: filled panel, no heavy outline, cream text, muted label, gold focus border.
- Chips: elev, cream label. Selected chip uses `primaryContainer`.
- Dialogs: panel, 20px radius, same button styles. Name dialogs on the party screen included.
- Snack bars: elev background, cream text.
- Progress indicators: gold, except the live mic which stays `bad`.
- Segmented button (shop): elev track, gold selected segment, onGold selected label.
- Dividers: `line`.

Page shell for every screen that is not the gameplay stage:

```text
Scaffold bg
  optional AppBar (back goes where it already goes)
  body padding 20
  one soft radial gold glow at the top (Alignment 0, -0.7, radius ~1.1,
  gold at 16% fading to bg by 55%). Put it once in the theme builder
  or a tiny StageBackground wrapper so screens do not each reinvent it.
```

Status-bar icons are light (`SystemUiOverlayStyle.light`).

## Shared widgets (`lib/widgets/`)

These widgets are used by both modes. Restyle them once so solo and LAN match.

- `ModeCard`, lobby `_ModeCard`, and `SoundPicker` rows: stop hardcoding `Colors.white`. Unselected = panel with a hairline. Selected = `primaryContainer`, gold radio or check, and the existing blurb still visible. Selected number uses onGold on gold, not white on gold. The host sound queue uses `SoundPicker`; the order badge must stay readable.
- `PlayerTile`, `ScoreRow`, `CoinChip`, `StatusChip`, `SectionTitle`: inherit the theme. Coin chip may become a pill (gold dot + tabular number) without changing what it shows.
- `CountdownView`: numeral in ReemKufi, gold, not white-on-purple.
- `WaveformBars` / `OverlayWaves`: original wave is cream at ~40%, the player’s wave is gold. Center the bars. Keep the existing progress highlight.
- `reveal_meters.dart`: label and value on one row, 8px bar underneath, full width. Color by grade (≥ 80 ok, ≥ 50 gold, else bad). The tonal caption stays. Do not put the numbers back if the widget intentionally hides them — the **reveal screen** should show the number next to the label; the widget can take an optional `showValue`.
- `DramaticScore`: the big number is gold (ReemKufi, ~88px) with a smaller muted `/100` on the same baseline. The shout under it uses `scoreLabel` and `scoreColor`. Do not invent new verdicts.
- `sprite_button.dart`: keep the play-frame images and the per-sound color. It is a library control, not a gold button.
- `avatar_view.dart` paw fallback: dark circle, gold paw, gold ring. Not a white disc.
- Gameplay `_StageCard` is shared. Replace the purple gradient (`#6D28D9` → `#2E1065`) with elev-to-bg, 28px radius, 1px gold-at-24% border, for every phase on both branches. Cream labels, not white-on-purple. Buttons with `backgroundColor: Colors.white` and `foregroundColor: #4C1D95` become gold / onGold in both branches. There are three of them (listen, handoff, ready).

## Screen specs

Keep every existing control. Do not change `onPressed` targets. Solo and LAN are specified to the same depth.

### Splash — `/`

Short beat, then `/home`. Not a place to add buttons.

- Full-screen bg plus the gold glow. No purple gradient.
- 96px circle, panel fill, 1.5px gold ring, gold paw.
- “Copy Cat” in ReemKufi ~40px, cream. Tagline muted, 16px.
- Gold progress indicator, 3px.

### Home — `/home`

Jobs, in this order:

1. Wordmark row: gold-ring paw (40px), “Copy Cat” ~28px ReemKufi, tagline muted, language pill on the end. The pill still switches language and still shows the **other** language (`EN` or `عربي`). Long-press on the title may keep opening `/design` until the mock is deleted.
2. One line of status: sound count, or the existing “record a 2–6s sound first” line when the library is empty.
3. Two ways to play, equal weight, both above the fold. Do not make LAN a row of small icons under a solo hero.
   - Panel “this phone”: one muted line (pass the phone, each player mimics on their turn) and a gold button `اللعب بموبايل واحد` to `/party`.
   - Panel “same Wi‑Fi”: one muted line (each player uses their own phone) and two equal buttons, min height 56: create room (`/lobby?host=1`) and join (`/lobby?host=0`). Outlined, not a second gold fill. My sounds is a quiet row under these panels, not a third tile squeezed between them.
4. The room-name field stays. Hosting still reads it. Do not remove it to simplify solo.
5. One panel row: equipped character (existing `AvatarView`) + “your character — tap for the shop” + coin balance + chevron. Whole row still goes to `/shop`.
6. One panel with the two existing fields: your name, room name for hosting. Same `onChanged` behavior, including cheat codes.
7. Footnote, muted, centered: play on the same Wi‑Fi. Credit line stays, muted, 11px.

Do not turn the name and room into the visual hero. Do not add mode picking here; modes live in the lobby. Do not shrink or hide create/join.

### Library — `/library`

App bar title + back to `/home`.

- If empty: a panel, not a bare sentence. Paw or mic icon, the existing empty copy, and the record action as the gold button.
- Each sound is a panel row: title, duration, waveform (cream), pitch line if present, sprite play button, delete. Play and delete do what they do now.
- Record block: duration choice stays. While recording, the live wave and the seconds are the hero; the mic icon is `bad`. The stop/save control is gold. Busy state disables the row and shows the existing message, not a new dialog.
- Import / download entry points stay where they are. Download remains a separate screen.

### Download — `/download`

Same chrome as library. List rows are panels. Thumbnails keep their shape. The action that saves a sound into the library is gold when it is the row’s primary; secondary actions are outlined. Empty and error text use muted / `bad`, on a panel, not default grey-on-white.

### Party setup — `/party`

Solo, pass-the-phone. App bar back to `/home`.

- Title “who is playing?” then the existing explanation in muted 14px.
- Ready-sound count as a pill.
- Player rows: avatar, name, “you” vs “guest”, tap to rename, remove if more than one. Rows are panels. Add-player is an outlined full-width button until the cap (5); then it disables and the existing max message shows in `bad`.
- Gold “start” pinned to the bottom of the screen, outside the list, so it survives a long player list. Disabled look when the library is empty; the existing mic-permission and empty-library messages stay above the button in `bad`.

Name dialog: panel, gold confirm, text cancel. Do not change dispose behavior.

### Lobby — `/lobby?host=1` and `?host=0`

This is the LAN game. It gets the same care as party setup. Actions stay: host sync, mode change still clears the sound queue, join by discovery or typed IP, leave room.

Host (`host=1`):

- Room panel: room name, open vs locked. Locked uses `elev` and a lock icon, never `Colors.grey.shade200` (unreadable on dark). One status line: waiting for friends, or how many phones are in.
- Player list. Mark the host and “this phone”. Empty state is a panel, not a bare line.
- “How to play”: one selectable card per `GameMode`. Selected card has a gold radio and the existing blurb. Unselected cards stay panel.
- Challenge mode only: “sounds (1–5, in order)” with `SoundPicker`. The order number is the queue position. The five-sound cap message stays in `bad`.
- Gold start pinned to the bottom, outside the list. The label still swaps between waiting for another phone, pick a sound first, and start. Disabled stays visible, with that reason as the label. Busy state keeps the gold progress line.

Joiner (`host=0`):

- Same room panel and player list.
- Read-only mode card: title plus the blurb, so a joiner knows the rules before the match starts.
- “Nearby rooms”: each discovered room is a full-width row (name, host, gold join). Empty state says no rooms yet, and points at the manual IP block under it.
- Manual IP: one field, one gold join, not a tiny trailing icon. Leave is an outlined button under that, full width. Do not make leave look like the primary.

### Gameplay

`/game?solo=1` is solo. `/game` without `solo` is LAN (`_buildLan`). Same phase visuals. LAN keeps the extra chrome solo does not have.

Shared stage, both branches:

- **Countdown:** gold numeral, muted caption.
- **Listening:** ear icon, status line, waveform with playhead.
- **Recording:** red mic, giant tabular seconds, “mimic now”, overlay waves (original cream, you gold).
- **Scoring:** gold spinner and the existing scoring line.
- **Handoff:** whose turn it is, gold “I’m ready”.
- **Reveal:** name, sound title, big gold score `/100`, `scoreLabel` in `scoreColor`, tonal caption, four meters, comparison waves labeled original vs your take. “Next” is gold and pinned if the column scrolls.
- **Recap:** same type ramp. No purple.

LAN header, only on `_buildLan`, kept and restyled:

- Round, gold sound title, coin chip.
- Player chips in a horizontal scroller. The active player uses `primaryContainer`. Totals stay on the chip.
- Power-ups: emoji + stock, 48px targets, 40% opacity when they cannot be used. Tooltips stay. Do not add paragraphs.
- Reaction row stays under the stage. Unaffordable reactions dim. Do not add reactions to solo.

Host-driven phase changes must keep working on every joiner.

### Results — `/results`

Both branches get the same layout. `_lanResults` also keeps rematch and gear, which solo does not have.

Shared:

- App bar back home, coin chip.
- Mode name, muted, when a mode exists.
- Winner avatar celebration, centered. A tie keeps the two-avatar row.
- Ranked `ScoreRow`s on one panel, winner row gold trophy, points tabular.
- Empty: one info panel, “no results yet”.
- Exactly one gold action (play again / rematch). Home and shop stay outlined.

LAN only: rematch still tells the host engine, and the existing snack bar still reports it. Do not drop gear or the winner’s equipped avatar.

### Shop — `/shop`

App bar, back home, coin chip.

- Segmented control: characters / emoji / power-ups. Selected segment gold.
- Characters: preview on a panel (existing `AvatarView`), price, owned check in `ok`, locked icon muted. Buy is gold when affordable, outlined-disabled when not. Equip is gold only when owned and not equipped; equipped shows a check, not a second buy.
- Emoji and power tabs: grid or list of panels, emoji large, price as a coin pill, the existing “not enough coins” snack bar. Do not add free sends or change stock rules.

## UX checklist (solo and LAN)

1. Can a new player tell what to tap in one second?
2. Is there exactly one gold button?
3. Are help lines muted and under the control they explain?
4. Does RTL put the back icon and chevrons on the correct edge? Use `Icon(Icons.arrow_back)` and `EdgeInsetsDirectional`, not left/right padding.
5. Does text stay cream on panel, and onGold on gold? White-on-gold and black-on-bg are failures.
6. Does a 360×640 phone scroll instead of overflowing? Pin only the primary continue/start button.
7. Are disabled actions still visible, with the reason in one muted or `bad` line?
8. Did any `onPressed`, route, provider, or `t()` key change? If yes, revert that part.
9. Did a solo edit delete, hide, or gate a LAN branch (`_buildLan`, `_lanResults`, lobby host/join, discovery, reactions, power-ups)? If yes, revert that part.

## Implementation order

1. `lib/stage_theme.dart` + `theme:` in `lib/main.dart`.
2. Shared widgets (`ui_bits.dart`, `sound_picker.dart`, `reveal_meters.dart`, `avatar_view.dart` fallback, `_StageCard`).
3. Home, with both play paths at equal weight. Then splash, library, download, shop.
4. Solo path: party setup, solo gameplay, solo results, name dialog.
5. LAN path, same pass standard: lobby host, lobby join, `_buildLan` header and reveal, `_lanResults`.
6. Delete `lib/screens/design_mock_screen.dart`, the `/design` route, and the home long-press only after both paths match this spec. Until then, leave them.

## Verify

- `flutter analyze`
- `flutter test` if `scoreColor` or scoring widgets change behavior, not just color.
- On a phone, solo: splash → home → party → one-phone game through reveal → results. Library empty and non-empty. Shop tabs. Arabic and English. Look for overflow.
- On a phone, LAN: from home, create room and join each open a lobby that matches this spec (room status, players, modes or nearby rooms, a clear primary). Start a match with a second phone if one is available and check the LAN header, a reveal, and LAN results. If no second phone, still confirm the lobby screens and that `_buildLan` is unchanged in behavior.

## Running on this PC

`storage.flutter-io.cn` and `storage.googleapis.com` do not resolve with the OS DNS. `android/build.gradle.kts` points Flutter engine artifacts at `http://127.0.0.1:8642/flutterio`. Start `node tool/maven_proxy.mjs` before `flutter run`. Phone device id used last time: `rs6dfmvk6xizhy85`. Launch with:

```text
D:\flutter\bin\flutter.bat run -d rs6dfmvk6xizhy85
```

An already-installed APK does **not** contain this restyle. Install a new debug build.
