# Gitagotchi — UX & Visual Design Spec
*Companion to the Gitagotchi design document. Covers every screen, state, sprite, and
interaction in v1. All mockups are drawn at or near the 60×20 minimum terminal size.*

---

## 0. Contents

1. Design principles
2. Visual language (color, glyphs, motion)
3. Layout system
4. Navigation model & keybindings
5. Screen catalog (cozy mode)
   - 5.1 First run / onboarding
   - 5.2 Main screen (anatomy)
   - 5.3 Pet state gallery
   - 5.4 Stat detail panel
   - 5.5 Friends list
   - 5.6 Friend view
   - 5.7 Compare view
   - 5.8 Help overlay
   - 5.9 Degraded, error & empty states
6. Sprite system (5 species, fully drawn)
7. Pet voice — copy guidelines
8. Open design questions
9. Dense mode — the btop-style theme (pixel-art pets, panels, meters, palette)
10. Scenes — day/night & the four seasons

---

## 1. Design principles

**P1 — The pet is the hero.** The top ~60% of the screen belongs to the creature and its
little world. Stats, chrome, and text live below a horizon line and never crowd the stage.
Nothing overlaps the pet except things the pet is interacting with (food bowl, mail).

**P2 — Legible magic.** Every visual is *explainable in one keypress*. The pet looks alive
and mysterious at a glance, but `s` (stat detail) shows exactly which GitHub signal drives
what you're seeing, in plain language, with the derivation. Deterministic ≠ opaque.

**P3 — One ambient prop at a time.** Flies, toys, the lonely window, the round belly —
each is a "vignette" cued by a stat. Showing several at once reads as noise. Rule: render
only the vignette for the *lowest* qualifying stat (with a small hysteresis band so it
doesn't flicker between two low stats). The screen always tells one story.

**P4 — Never block, never nag.** No modal ever interrupts the pet for network activity.
Refresh is a one-cell spinner in the footer. Copy observes, it doesn't guilt-trip
("Zeruko naps pointedly" — never "You haven't committed in 3 days!"). The anti-burnout
stance from the design doc is a *tone* requirement, not just a stat.

**P5 — Chunky is the charm.** 4 fps, hard frame steps, no easing. Motion vocabulary is
small and repeatable: swap, drift, blink, float. A Tamagotchi wobbles; it does not tween.

---

## 2. Visual language

### 2.1 Glyph tiers (unicode policy)

Everything ships in two render tiers, selected at startup (locale/`$TERM` sniff) and
overridable with `--ascii`:

| Tier | Used for | Examples |
|---|---|---|
| **A — pure ASCII** | guaranteed baseline, CI, dumb terminals | `[M 2]`, `[R 1]`, `<3`, `zZz`, bars of `#` and `-` |
| **B — common unicode** | default on modern terminals | `✉`, `⎘`, `❤`, `💤`, `█ ░` bars, `·` ambience |

Every glyph in this spec is written Tier-B with its Tier-A fallback noted the first time
it appears. Sprites themselves are Tier-A skeletons (see §6) so species art never depends
on the tier.

### 2.2 Color roles (ANSI-256)

| Role | Color | Notes |
|---|---|---|
| Pet body | linguist color → nearest ANSI-256 | e.g. Python `#3572A5`→67, Rust `#DEA584`→180, JS `#F1E05A`→221, Go `#00ADD8`→38, Ruby `#701516`→88 |
| Pet, sick/hibernating | same hue + faint SGR (`\e[2m`) | pale = unwell; hue is identity and never changes |
| Chrome (borders, labels) | 240 (dim gray) | recedes; content pops |
| Stat bar fill | ramp: `<20`→196 red, `20–49`→214 amber, `50–100`→77 green | empty track always 238 |
| Happiness hearts | 204 (soft red) | |
| Mail envelope `✉` | 221 (yellow) | attention without alarm |
| Review scroll `⎘` | 45 (cyan) | "work" color, distinct from mail |
| Security pre-warning | 203 | pairs with sick state |
| Pet-voice line | 250, italic where supported | quiet narration |

Rules: never pure black/white backgrounds are assumed (works on light terminals); color
is always redundant with a glyph or number (colorblind-safe); the *only* saturated large
area on screen is the pet itself — bars are thin, chrome is gray.

### 2.3 Motion constants (at 4 fps, 1 tick = 250 ms)

| Motion | Spec |
|---|---|
| Idle frame swap | every 2–3 ticks, ±1 tick jitter (session-local RNG) |
| Blink | face swaps to closed-eyes for 1 tick, randomly every 3–8 s |
| Wander | ±4 columns from home column, 1 col/tick, ~20% chance to start per 5 s; never during eat/sick/hibernate |
| Bliss float | happiness 100 only: wander stops, pet drifts home to the centre 1 col/tick, then leaves the stage entirely — lerped to the middle of the **screen** over 13 ticks (`BLISS_T` 0→100, +8/tick) and drawn on the z-layer **above every panel**, bobbing 1 row every 8 ticks once arrived. The three-heart halo follows its head, unpenned from the stage. Idle only — a host stands at the stage edge for its guests, and every other state is busy somewhere specific. Leaving 100 (or any state change) brings it home the same way it left. Cozy has no z-layer, so there the float lerps to the middle of its own stage |
| Bliss bar | happiness 100 only: the meter drops the red→green ramp and goes **all green**, blinking between the two greens on a 2-tick beat, with 3 gold `✦` running the length of it and twinkling out at the end (they lift a row clear of the bar where there's headroom; in the dense column happiness is the panel's top row, so usually there isn't) |
| Eating sequence | 12 ticks (3 s), locks all other motion, ends with `+N` float |
| Float-ups (hearts, `+N`, `zZz`) | 1 row/tick, spawn at pet, expire at stage top |
| Celebrate burst | 8 ticks of confetti chars `* · ✦` falling 1 row/tick |
| Hibernation breathing | cocoon expands/contracts 1 char every 4 ticks |

---

## 3. Layout system

Minimum 60×20. The screen divides into four fixed zones; extra terminal size adds air to
the **stage**, never more chrome.

```
┌──────────────────── title bar (1 row) ────────────────────┐
│                                                           │
│                     STAGE (flexible,                      │
│                     min 7 rows)          medal shelf      │
│                                          (right side)     │
│ ── horizon ────────────────────────────────────────────── │
│                     voice line (1 row)                    │
│                                                           │
│                     DASHBOARD (6 rows):                   │
│                     happiness headline + 6 stat bars      │
│                                                           │
└──────────────────── footer bar (1 row) ───────────────────┘
```

- **Title bar** carries identity (name · species · life stage) on the left and live
  indicators (`✉`, `⎘`) pinned to the right — indicators must sit in the same place in
  every screen so the eye learns where "new" appears.
- **Stage** is the pet's territory. The pet's *home column* is horizontal center; wander
  range is clamped to stage width. The horizon line is drawn with `·` (Tier A: `.`) —
  it's ground, not a border.
- **Medal shelf** hangs on the stage's right edge, max 2 rows; overflow renders `+3`.
- **Dashboard** shows happiness as the headline plus the six most *actionable* stats.
  The other three (curiosity, wisdom, health) live one keypress away in stat detail (§5.4)
  — ten bars at once is a spreadsheet, not a pet.
- **Footer** is the constant control surface: keys on the left, sync status on the right.

Responsive rules: width < 60 or height < 20 → "too small" card (§5.9). Width ≥ 80 → stat
bars widen from 12 to 20 cells and the two columns gain a gutter; the pet does not scale
(sprites are fixed-size; scaling ASCII art destroys it).

---

## 4. Navigation model & keybindings

One flat home screen, three sub-screens, two overlays. Everything is reachable in ≤ 2
keypresses, and `Esc`/`q` always walks back one level.

```
                       ┌───────────┐
      ?  ◂───────────▸ │   MAIN    │ ◂───────────▸  s
   help overlay        └─────┬─────┘             stat detail
                             │ f
                       ┌─────▾─────┐   ↵    ┌─────────────┐
                       │  FRIENDS  │ ─────▸ │ FRIEND VIEW │
                       │   list    │ ◂───── └──────┬──────┘
                       └─────┬─────┘   Esc         │ c
                             │ c (on a row)  ┌─────▾─────┐
                             └─────────────▸ │  COMPARE  │
                                             └───────────┘
```

| Key | Context | Action |
|---|---|---|
| `f` | main | friends list |
| `s` | main, friend view | stat detail (all 10 stats + derivations) |
| `c` | friends list row, friend view | compare that friend vs you |
| `r` | anywhere | force refresh (respects tier cadence; spins in footer) |
| `?` | anywhere | help overlay |
| `↑↓` / `jk` | lists, stat detail | move selection |
| `↵` | friends list | open friend view |
| `Esc` | sub-screen/overlay | back one level |
| `q` | main | quit (with a 1-frame wave); on sub-screens, same as Esc |

The footer of every screen shows exactly the keys valid *right now* — the footer is the
menu; there is no other menu.

---

## 5. Screen catalog

### 5.1 First run / onboarding

There is no setup wizard — auth resolution *is* the onboarding, rendered as theater.
Four beats, ~6 seconds total, any key skips ahead.

**Beat 0 — power-on (the neon sign lights up):**

The `gitagotchi` wordmark ignites like a real neon sign — the terminal port of
`gitagotchi-neon.html`. Each letter buzzes alight in sequence (a dark pre-ignition
flicker, a white-hot ignition flash, then a settle), lit blue→purple across the sign,
then holds on a steady hum. The sign **stays lit** while Beat A's boot lines cascade in
beneath it — one screen, not a separate console. Colour terminals ≥ 81 cols only;
anywhere smaller (or ASCII), Beat 0 is skipped and Beat A opens on a plain centred
`gitagotchi` title instead. First-run only, or on demand via `--onboarding`.

**Beat A — boot (auth resolution made visible), below the lit sign:**

```
        ███  █  ████  ███  ████  ████ ████  █   █  █      ← the sign, still humming
        ...  ...  the GITAGOTCHI wordmark stays lit  ...

           ✓ found gh token           @will
           ✓ fetching account         id 3151702
           ✓ deriving pet             seed a41f…
           ● first sight…
```

Each line lands as its call completes, appearing directly under the wordmark. If auth
falls through to unauthenticated, the first line reads `◦ no token — public data only`
and boot continues; no error, no prompt. (On a plain terminal the sign is a centred
`gitagotchi` text title instead, with the same lines beneath.)

**Beat B — the egg cracks open (8 ticks), centred on the stage:**

The pixel egg — the same half-block sprite the pet is drawn in, hue-shifted through the
account's language palette — sways idle for a few ticks, then splits `crack_1 → crack_2`
as a fracture opens across the shell. Centred by the sprite's true width. On a
non-truecolor / ASCII terminal it falls back to the little `.-.` / `( ✦ )` / `` `-' ``
egg, tilting and cracking the same way.

```
                        ▄▄▄▄
                      ▄██▓▓██▄            the egg wobbles, then a
                     ████▓█████           hairline crack forks open
                     ██████████           across the shell
                      ████████
                       ██████
                       ( tap… )
```

**Beat C — reveal:**

```
                    ✦   \|/   ✦
                      ≼(o‿o)≽
                       (   )~
                        ˘ ˘

                 Hi my name is Zeruko
             the axolotl · adult · est. 2014
```

…then the frame dissolves into the main screen (banner text slides down into the title
bar). Because first-run-ness is inferred from an empty cache, the reveal **replays on any
new machine** — that's the invariant working *for* the UX: your pet hatching again on a
new laptop is a feature, and it proves nothing was stored.

For accounts genuinely younger than 7 days there is no crack and no reveal — the egg is
the pet (§5.9). Instead Beat B becomes a short **egg beat**: the pixel egg settles in,
wobbling idle beneath `a quiet egg · hatches in Nd`, with the name and species still
secret. It then hands off to the main screen, which holds the same egg.

### 5.2 Main screen — anatomy

```
┌─ Zeruko · axolotl · adult ───────────────── [✉ 2] [⎘ 1] ─┐
│                                                          │
│                                             ╭ medals ──╮ │
│           \|/                               │ PS³ YOLO │ │
│         ≼(o‿o)≽                             │ QD   GB  │ │
│          (   )~                             ╰──────────╯ │
│           ˘ ˘                                            │
│ ························································ │
│  “Merged #482 four hours ago — Zeruko is well fed.”      │
│                                                          │
│  happiness ❤ ██████████████████░░░░░░ 78                 │
│                                                          │
│  hunger ██████████░░  71     mood   ████████░░░░  68     │
│  energy ████░░░░░░░░  34     social ███████░░░░░  60     │
│  clean  ██████████░░  85     fit    ██████░░░░░░  55     │
│                                                          │
│  ▸ energy low — 14 days above your usual pace, no        │
│    rest gap ≥ 6h in the last 24h                         │
│                                                          │
└ [f]riends [s]tats [r]efresh [?]help [q]uit ──── ✓ 12s ───┘
```

Callouts, top to bottom:

- **Title bar** — `name · species · life stage` (identity, never changes mid-session).
  Right-pinned live indicators: `[✉ 2]` mail count (Tier A: `[M 2]`) and `[⎘ 1]` pending
  review requests (`[R 1]`). Both are OSC 8 hyperlinks; both also appear in stat detail
  with their printed URLs for terminals without hyperlink support. When a new one
  arrives, the badge blinks twice (2 ticks on/off) and the pet perks its ears — badge and
  pet react together, teaching the mapping without a tutorial.
- **Stage** — pet at its wander position; medal shelf on the right edge (max 2 rows,
  overflow renders as `+3`; empty shelf renders nothing — no sad empty box).
- **Horizon** — `·` ground line, full width.
- **Voice line** — one sentence of narration (§7), rotates every ~45 s among currently
  true lines. Never scrolls, never wraps to two lines; truncate with `…`.
- **Happiness headline** — double-width bar with `❤` (Tier A: `<3`). When happiness > 80,
  hearts float from the pet. When the misery cap is active, the bar caps visually at 60
  with a dim notch at the true composite value and the insight line explains it.
- **Six core bars** — hunger, energy, clean / mood, social, fit. Two columns, always the
  same six in the same order (spatial memory beats dynamic sorting). Curiosity, wisdom,
  health live in stat detail — surfaced here only via the insight line or sick state.
- **Insight line** (`▸`) — the single most actionable derivation right now: the lowest
  stat's "why". This is the pet's needs made concrete. At most 2 lines; disappears when
  everything is ≥ 50 (a happy screen is a quiet screen).
- **Footer** — valid keys left, sync cell right: `✓ 12s` (age of freshest data) →
  `⟳` spinner while a tier refreshes → degradation states in §5.9.

### 5.3 Pet state gallery (stage-zone crops)

**Sleeping** — a rest gap ≥ 6h is detected in your event stream, or local night hours
during your inactivity. Dashboard labels dim one step; voice goes quiet:

```
│               Z                          │
│           \|/   z                        │
│         ≼(-.-)≽                          │
│          (___)~                          │
│ ····································     │
│  “Quiet on the feed. Zeruko sleeps       │
│   while you do.”                         │
```

**Eating — the payoff moment.** The fast tier detects a newly merged PR. Sequence locks
all other motion for 12 ticks:

```
  eat_1 (bowl slides in)   eat_2 ×3 (munch)      eat_3 (done)
      \|/                      \|/                   \|/   +18
    ≼(o.o)≽    ╔ #482 ╗      ≼(>u<)≽               ≼(^‿^)≽
     (   )~     \≋≋≋≋/          \≋≋/ (   )~          \__/ (   )~
```

Title bar flashes `PR #482 merged` for 8 ticks (it's a hyperlink to the PR). `+18`
floats up in the bar's green. If this pushes happiness past 80, hearts follow. This is
the single most-tuned animation in the app — it's the moment people screen-record.

**Celebrating** — new medal or follower burst detected:

```
│     ✦   ·   *   ✦   ·                    │
│        \(^‿^)/                           │
│         (   )                            │
│  “Starstruck ×2 — the shelf is getting   │
│   crowded.”                              │
```

**Sick** — health < 40 (self only). Pet renders faint (SGR 2), thermometer `▍` (Tier A
`|=`); the health bar temporarily replaces `clean` in the dashboard so the cause is on
the main screen while it matters:

```
│           \¡/                            │
│         ≼(x.x)≽ ▍                        │
│          (   )~                          │
│  “2 high Dependabot alerts on            │
│   plugin-core. Medicine is one           │
│   `npm audit fix` away.”                 │
```

**Hibernating** — ≥ 30 days without public events. Cocoon breathes (expands 1 char every
4 ticks); every bar shows its frozen value prefixed `❄` (Tier A `*`):

```
│          ⎛⎛  zZ  ⎞⎞                      │
│         ⎛⎛ (-.-) ⎞⎞                      │
│          ⎝⎝______⎠⎠                      │
│  “31 days quiet. Zeruko hibernates —     │
│   stats frozen, no judgment. The first   │
│   push wakes them.”                      │
```

Wake-up: cocoon cracks like the onboarding egg (reused frames), pet does one stretch,
stats fade from `❄` values to live values over 4 ticks.

**Drowsy pre-hibernation** (21–29 days): yawning idle frames, a small `💤?` hint drifts
up occasionally. This is the only advance warning; it's gentle by design.

**Ambient vignettes** — one at a time, cued by the lowest qualifying stat (P3), each with
a 5-point hysteresis so the scene doesn't flap:

| Stat trigger | Vignette |
|---|---|
| cleanliness < 40 | flies `.·°` orbit the pet, 2-frame swap |
| social < 30 | a small window `┌─┐` appears top-left; pet sits facing it |
| curiosity < 30 | no toys on the floor (their *absence* is the cue); at ≥ 60 a ball `●` appears and the pet bats it between two columns |
| fitness < 35 | body line widens — the round belly frame variant |
| fitness ≥ 80 | stretch animation joins the idle rotation (~every 30 s) |

### 5.4 Stat detail panel (`s`)

The legibility screen (P2). All ten stats; the selected one expands to show its value,
its human "why", and its literal GitHub source:

```
┌─ stats · Zeruko ────────────────────────── [✉ 2] [⎘ 1] ──┐
│                                                          │
│ ▸ hunger       ██████████░░  71                          │
│    3 PRs merged in the last 7d, newest 4h ago            │
│    src: search  is:pr author:will is:merged  · decays ½/2d │
│                                                          │
│   energy       ████░░░░░░░░  34                          │
│   mood         ████████░░░░  68                          │
│   fitness      ██████░░░░░░  55   · 9 of last 21 days    │
│   cleanliness  ██████████░░  85                          │
│   curiosity    ███░░░░░░░░░  25                          │
│   social       ███████░░░░░  60                          │
│   wisdom       █████████░░░  74   · (o-o) earned         │
│   health       ██████████░░  90                          │
│   ─────────────────────────────────────                  │
│   happiness    █████████░░░  78                          │
│                                                          │
└ [jk] select   [↵] open on github   [Esc] back ───────────┘
```

- `↵` on a stat opens its source on GitHub via OSC 8 (hunger → your merged-PR search,
  cleanliness → the stale-issue list, health → the security tab). The stat panel is
  therefore also the *fix-it* menu: every low bar links to the exact page that raises it.
- When the misery cap is active, the happiness row reads
  `happiness ██████░░░░░░ 60 ⚠ capped — hunger 12 < 20` in amber.
- On a friend, health renders as `health ─ private · by design` (dim, not an error).

### 5.5 Friends list (`f`)

```
┌─ friends · following 23 ─────────────────────────────────┐
│                                                          │
│ ▸ mona          Pabo      ^ᴥ^    ❤ 82                    │
│   defunkt       Kilu      (oo)   ❤ 91                    │
│   ashtom        Zerudo    o/|\   ❤ 77                    │
│   octocat       Vemi      ≼o≽    ❤ 64                    │
│   busydev       Ruko      (o)>   ❤ 58                    │
│   quietfriend   Nubi      ⎛-⎞    💤 hibernating · 41d    │
│   newdev        —         (✦)    egg · hatches in 3d     │
│                                                          │
│                                                          │
└ [jk] move  [↵] visit  [c]ompare  [Esc] back ── ✓ 2m ─────┘
```

- Row = login · pet name · species **mini-glyph** (a 1-line block every sprite file must
  provide, §6.6) · happiness, or a state badge that overrides it. Mini-glyphs render in
  each pet's own linguist color — the list is a little crowd.
- Sort: awake friends by happiness desc; hibernating pinned to the bottom with day
  counts. The doc's "see who's gone quiet at a glance" lives exactly here.
- Rows render instantly from the 5-minute cache; not-yet-fetched rows show name + `···`
  and fill in as responses land. The list never blocks on the network (P4).

### 5.6 Friend view (`↵` on a row)

The main screen, re-skinned by what's knowable about someone else:

- Title: `@mona's Pabo · cat · adult`. No `✉`/`⎘` slots — their mail is theirs.
- No health anywhere except the dim `private · by design` row in stat detail.
- Voice line switches to third-person observation ("Pabo has been reviewing all week —
  someone's earning wisdom.").
- Footer adds `[c]ompare`. `r` refreshes their public data (respecting the 5-min cache).

### 5.7 Compare view (`c`)

```
┌─ you · Zeruko ────────────┬─ @mona · Pabo ──────────────┐
│          \|/              │         /\_/\               │
│        ≼(o‿o)≽            │        ( o‿o )              │
│         (   )~            │         (   )~              │
│          ˘ ˘              │          ˇ ˇ                │
│ ························· │ ··························· │
│  happy  ████████░░  78    │   ████████▓░  82  ◂         │
│  hunger ███████░░░  71  ◂ │   ██████░░░░  58            │
│  energy ███░░░░░░░  34    │   ████████░░  76  ◂         │
│  fit    ██████░░░░  55    │   █████████░  88  ◂         │
│  social ██████░░░░  60  ◂ │   █████░░░░░  51            │
│  medals [PS³][YOLO]       │   [PS²][GB][SS]             │
│                           │                             │
└ [Esc] back ─────────── friendly rivalry, not a leaderboard ┘
```

- `◂` marks the higher value per row; both pets stay animated (idle frames only).
- Deliberately **no total-winner line** — the footer literally states the stance. Health
  is excluded from the rows shown (it wouldn't be a fair column).
- This is the shareable screen: `gh pet compare mona --snapshot` prints this frame once
  to stdout as plain text and exits, ready to paste anywhere.

### 5.8 Help overlay (`?`)

A centered card over the dimmed main screen: the keybinding table from §4, one line of
philosophy ("your pet is computed from your GitHub account — nothing is stored, nothing
is sent anywhere"), and the version string. `Esc` or `?` closes.

### 5.9 Degraded, error & empty states

**Unauthenticated** — a permanent dim status line above the dashboard (it cannot be a
dismissible banner, because dismissal would be state — the invariant makes this decision
for us):

```
│  ◦ public data only · `gh auth login` unlocks mail,      │
│    health & private contributions · refresh: 10 min      │
```

No `✉`/`⎘` slots. Everything else works.

**Offline / rate-limited** — the pet keeps rendering from cache; only the footer sync
cell degrades, in steps: `✓ 12s` → `⟳` → `⌛ retrying in 40s` → `offline · data 9m old`.
The pet's behavior never changes because of the network (P4) — a laggy API must never
read as a sad pet.

**Window too small** (< 60×20):

```
        ┌────────────────────────┐
        │   (o.o)                │
        │   zeruko needs room:   │
        │   60×20 · now 48×14    │
        └────────────────────────┘
```

Live-updates on SIGWINCH; the moment the window is big enough, the full screen returns.

**Egg** (account < 7 days): the stage is the egg with occasional wiggles; instead of the
dashboard, a single `warmth` bar reflecting activity so far, plus `hatches in 4d`
(derived: 7 − account_age). First contributions make the egg wiggle more. Hatch day
plays Beat B→C from onboarding.

**Zero public repos**: pet uses the seed-palette fallback color (per the design doc);
voice nudges: "A first public repo would give Zeruko its true colors."

**Zero following**: friends screen empty state — "Follow someone on GitHub and their pet
appears here. A friend's pet is computed from their public account — nothing to invite,
nothing to sync."

**Medals unavailable** (scrape failed): the shelf renders `medals: unavailable` in dim
gray. Never a dialog, never a crash (per §4 of the design doc).

**Quit** (`q`): one frame of `(o.o)/  bye!`, then the alternate screen buffer restores —
the terminal is exactly as it was.

---

## 6. Sprite system — five species, drawn for real

### 6.1 Canvas & layer spec

Every species renders on a fixed **14 × 4** cell canvas (egg and hatchling smaller).
Draw-time composition, back to front:

```
1. base frame     (species file, pure ASCII skeleton, face slot = @@@)
2. pattern layer  (overlay chars placed on body-interior cells marked in the file)
3. accessory      (anchored to the species' declared neck/head anchor cell)
4. face           (3–5 chars substituted into the @@@ slot, from the face table)
5. color          (whole sprite tinted with the linguist ANSI color)
```

Each species file declares: frame blocks by name, the face slot position per frame, the
body-interior cell mask (where pattern chars may land), a neck anchor and a head anchor
(where accessories attach), and a 1-line `mini` block for list rows. Faces, patterns,
and accessories are **global** — drawn once, work on all 100 species. The hibernation
cocoon is also global (the pet is hidden inside it anyway); only its tint is per-pet.

### 6.2 Species 1 — Axolotl (complete reference set)

The reference implementation: every frame block a species file must (or may) provide.

```
idle_1              idle_2              sleep_1             sleep_2
    \|/                 ~|~                              Z
  ≼(@@@)≽             ≽(@@@)≼             \|/   z            \|/  Z
    (   )~              (   )               ≼(@@@)≽   z       ≼(@@@)≽
     ˘ ˘                 ˘ ˘ ~               (___)~            (___)~

eat_1               eat_2               eat_3
    \|/                 \|/                 \|/   +N
  ≼(@@@)≽             ≼(@@@)≽             ≼(@@@)≽
    (   )~  \≋≋≋/       \≋≋/ (   )~         \__/ (   )~

sick                celebrate           hatch_1 (shared w/ onboarding)
    \¡/               ✦  \|/  ✦              .-.
  ≼(@@@)≽ ▍            \(@@@)/              ( ✦ )
    (   )~               (   )               `-'
                          ˘ ˘

mini:  ≼o≽
```

Face slots: `@@@` is replaced per the face table (§6.5) — e.g. idle at high happiness
composes to `≼(o‿o)≽`, sleep always forces `-.-`, sick always forces `x.x`, eat_2 forces `>u<`.
The gill crest (`\|/` ↔ `~|~`) is the species' signature two-frame motion.

### 6.3 Species 2–5 (idle pair + signature frame each)

**Cat** — signature: tail flick & the loaf.

```
idle_1          idle_2          sleep ("the loaf")
  /\_/\           /\_/\            /\_/\   z
 ( @@@ )         ( @@@ )          ( @@@ )
  (   )~          (   ) /          (___)
   ˇ ˇ             ˇ ˇ

mini:  ^ᴥ^
```

**Octopus** — signature: tentacle sway (whole lower row alternates).

```
idle_1          idle_2          celebrate
  .───.           .───.          ✦ .───. ✦
 ( @@@ )         ( @@@ )          ( @@@ )
 /|/|\|\         \|\|/|/          \|/|\|/

mini:  o/|\
```

**Chick** — signature: head-bob peck; the accessory anchor sits on the crest feather.

```
idle_1          idle_2          eat_2 (pecks the bowl)
   \\,             \\,              \\,
  (@@@)>          (@@@)>           (@@@)
   (  )            (  )              v≋≋/ (  )
   ¨ ¨              ¨¨

mini:  (o)>
```

**Blob** — the simplest archetype; the canonical body for showing patterns (§6.4).
Signature: the squish.

```
idle_1          idle_2 (squish)     sleep
   ____            ______             ____
  ( @@@ )         ( @@@  )           ( @@@ )   z
 (      )        (~      ~)         (______)
  ‾‾‾‾‾‾           ‾‾‾‾‾‾

mini:  (oo)
```

These five bodies are five of the ~10 archetypes; the remaining species are archetype ×
head/ear/tail variants per the design doc, each still shipping its own file.

### 6.4 Pattern layer (second language → texture)

Pattern chars land only on cells in the body-interior mask. On the blob:

```
solid            spots            stripes          patches
   ____             ____             ____             ____
  ( @@@ )          ( @@@ )          ( @@@ )          ( @@@ )
 (      )         ( • ∘ •)         ( ≋≋≋≋ )         ( ▒▒   )
  ‾‾‾‾‾‾           ‾‾‾‾‾‾           ‾‾‾‾‾‾           ‾‾‾‾‾‾
```

Tier-A fallbacks: spots `o .`, stripes `= =`, patches `%%`. Pattern chars render one
shade dimmer than the body color so texture never fights the silhouette.

### 6.5 Face layer (happiness × condition)

Faces are 3 chars (eyes·mouth·eyes) dropped into the `@@@` slot. The expression
tracks **overall happiness**, not mood alone, so the face agrees with the happiness
number on the same card — a middling pet doesn't beam. Happiness maps to five
buckets: `≥80` ecstatic, `≥65` content, `40–64` neutral, `25–39` grumpy, `<25`
miserable (mood still colours the temper insight copy, but no longer drives the mouth):

| Source | Face | Reads as |
|---|---|---|
| happiness ≥ 80 | `^‿^` | beaming |
| happiness ≥ 65 | `o‿o` | soft smile |
| happiness 40–64 | `o.o` | default (straight) |
| happiness 25–39 | `ò~ó` | scowl (Tier A `>_<`) |
| happiness < 25 | `;_;` | droop |
| energy < 25 (overrides mouth) | `¬.¬` | eye-bags, the frazzle |
| blink frame (1 tick) | `-.-` | |
| sleeping | `-.-` | |
| sick (forced) | `x.x` | |
| eating (forced, eat_2) | `>u<` | chomp |
| wisdom ≥ 60 | eyes bridge: `o-o` | tiny spectacles, composable with any mouth |

Priority: forced states > energy override > happiness. Spectacles compose (`ò-ó` = wise and
unhappy — a code reviewer).

### 6.6 Accessory layer (profile facts)

Anchored to the neck/head anchor each species declares:

| Accessory | Trigger (from design doc) | Glyph @ anchor | Tier A |
|---|---|---|---|
| bandana | bio set | `«▼»` at neck | `<v>` |
| bowtie | `hireable: true` | `»◊«` at neck | `>o<` |
| collar tag | public org member | `–⊙–` at neck | `-o-` |
| tiny crown | staff/Pro | `.^.` on head | same |
| bare | none | — | — |

One accessory max (doc's precedence order applies). On the cat idle_1 with a bowtie:

```
  /\_/\
 ( o‿o )
  »◊«
  (   )~
```

### 6.7 Life stages (size + additions)

```
egg             hatchling (2 rows)   kid (3 rows)      adult          elder
  .-.               (@@@)              /\_/\             full          full
 ( ✦ )               ˘˘               ( @@@ )            canvas        canvas +
  `-'                                  ˘ ˘                             beard ≡
                                                                       under chin
```

- Hatchling = head-only mini form of its species (declared as `young` block).
- Elder adds `≡` under the face slot and, with wisdom ≥ 60, spectacles — the elder-wise
  combo (`(o-o)` over `≡`) is the most decorated a pet ever gets, and it's all earned.

### 6.8 Mini glyphs

Every species file provides a ≤ 5-char `mini` block (shown in §6.2–6.3) used in friends
list rows, rendered in the pet's own color. Overriding states replace it: `(✦)` egg,
`⎛-⎞` hibernating.

---

## 7. Pet voice — copy guidelines

The voice line is the app's personality. Rules:

1. **Observe, never scold.** The pet notices; it does not demand. Guilt-trip phrasing
   ("you haven't…", "don't forget to…") is banned. The pet's own state carries the
   message — the copy just narrates it.
2. **Always name the fact.** Every line embeds the concrete GitHub-derived detail
   (a PR number, a day count, a repo name). Vague lines ("Zeruko seems hungry") read as
   fake; specific ones ("no merges in 3 days — the bowl echoes") read as alive.
3. **The pet sides with rest.** Overwork lines celebrate stopping, not output. This is
   where the anti-burnout mechanic becomes audible.
4. **One sentence, ≤ 56 chars ideally, hard-truncate with `…`.** Third person, present
   tense, pet's name or pronoun as subject.

Sample line pools (2–4 per condition, rotated by session-local RNG):

| Condition | Lines |
|---|---|
| hunger high (fresh merge) | "Merged #482 four hours ago — Zeruko is well fed." / "Two merges today. The bowl runneth over." |
| hunger < 20 | "Three dry days. Zeruko circles the empty bowl." / "The bowl echoes." |
| energy < 25 | "14 days above your usual pace. Zeruko naps pointedly." / "Zeruko left a tiny note: 'take a walk'." |
| resting detected | "Quiet on the feed. Zeruko sleeps while you do." |
| cleanliness < 40 | "6 stale issues on plugin-core. The flies have opinions." |
| social < 30 | "Zeruko watches the window. When did you last review a friend's PR?" |
| curiosity ≥ 60 | "A new language this month! Zeruko found a new toy." |
| mood: miserable | "Two changes-requested this week. Zeruko sulks in solidarity." |
| friend view | "Pabo has been reviewing all week — someone's earning wisdom." |
| hibernating (friend) | "Nubi has been curled up for 41 days. Say hi when they're back." |

---

## 8. Open design questions (recommendations attached)

1. **Should `✉` show on friends' pets?** Notification counts are private (self-only API)
   — currently the slot just doesn't exist on friend views. Recommend keeping it that
   way; an empty slot would imply something knowable that isn't. *(Spec'd in §5.6.)*
2. **Bar count on main screen.** This spec picks 6 + happiness (over the doc's implied
   all-visible) and demotes curiosity/wisdom/health to stat detail. If playtesting shows
   people miss wisdom's slow climb, promote it to a right-column seventh bar at ≥ 80-col
   widths only.
3. **Voice-line frequency.** 45 s rotation is a guess; too chatty and it becomes UI
   noise, too slow and people never see line variety. Tune during phase 2.
4. **Compare with a hibernating friend** renders their cocoon and frozen bars — decide
   whether `◂` markers still apply (recommend yes; frozen values are still values).
5. **`--snapshot` scope.** Spec'd only for compare; a plain `gh pet --snapshot` (own pet,
   one frame, stdout) would make README/CI embedding trivial and is nearly free — 
   recommend adding to phase 1 since it's also the perfect test harness output.

---

## 9. Dense mode — the btop-style theme

*(See the companion mockup `gitagotchi-btop-mockup.html` for this section rendered in
full color.)* Dense mode is the **default at ≥ 110×32 with truecolor**; the §5 minimal
layout becomes "cozy mode", the automatic fallback for 60×20 terminals and Tier-A color.

### 9.1 Layout — five titled panels

btop's grammar: every region is a bordered box whose **border color is its identity**,
with the title embedded in the border (`┤ vitals ├`) and its hotkey pinned top-right.

```
┌ header: logo · @login · id · lang ── [✉2] [⎘1] · api 187/5000 · clock ┐
├ zeruko (pet, linguist color) ──────┬ vitals (green) ──────────────────┤
│  pixel-art pet · medal shelf       │ happiness headline meter         │
│  ground line · nameplate · voice   │ 9 stat rows: label·spark·meter·n │
├ activity · events/day · 60d (contribution-green) ─────────────────────┤
│  block-column graph · 90d-baseline dashed line · gap/merge annotations│
├ friends (blue) ────────────────────┬ feed (purple) ────────────────────┤
│  proc-list table w/ ❤ mini-meters  │ tagged liveness log: merge/review │
└ footer: key buttons ──────────────────────────────── ✓ synced 12s ago ┘
```

**Header bar** (dense mode only): `gitagotchi v1.0 · @login · id · top-language` left;
right-pinned: `[✉ 2]` (pulses on arrival) `[⎘ 1]` · `api 187/5000` (rate-limit budget,
green while healthy) · live clock. **Footer**: btop-style key buttons (`[f friends]`,
key letter in red, label muted) left; `✓ synced 12s ago` right, degrading per §5.9.

**Friends table** (dense): columns `login · pet (mini-glyph in their color + name) ·
lvl · ❤ happy (8-cell mini gradient meter + value) · state`; selected row gets a blue
tint + `▸`; hibernating/egg rows swap the meter for their state badge.

**Panel hotkeys**: each panel's key is pinned in its top-right border (`friends… f`),
so the footer and the panels teach the same keys twice.

### 9.2 The pet is pixel art (half-block rendering)

Dense mode upgrades sprites from ASCII to **terminal pixel art** using the half-block
technique: each cell prints `▀` with the *foreground color = top pixel* and *background
color = bottom pixel* — two vertical pixels per cell, full truecolor, plain ANSI, no
image protocol. A 24×18-pixel sprite costs 24 columns × 9 rows.

- Sprite source: tiny palette-indexed text grids per species (24×18 chars, one letter
  per palette slot: `O` body, `D` outline, `W` belly, `K` eyes, `P` gills, `R` blush) —
  same layering rules as §6 (pattern chars recolor body cells, accessories overdraw
  anchors, faces swap eye/mouth pixels).
- The body palette is generated from the linguist color (base, −20% lightness outline,
  +25% belly), so all 100 species recolor for free.
- Animation stays chunky: 2 frames (gill sway / tail flick) at ~600 ms + a blink frame
  every 3–8 s.
- **Render ladder:** truecolor half-block → ANSI-256 half-block (nearest color) →
  Tier-A ASCII sprite (§6). Sixel/kitty graphics deliberately *not* used in v1 —
  half-blocks work everywhere ANSI does, including tmux.

Reference sprite — the axolotl from the mockup, 24×18, palette-indexed
(`.` transparent · `O` body · `D` outline · `W` belly · `K` eyes/mouth · `P` gills ·
`R` blush · `S` shading). Frame 2 shifts the gill pixels outward one column and flicks
the tail; the blink frame replaces the `KW` eye pairs with `DD`:

```
........................
....PP............PP....
......DOOOOOOOOOOD......
.....DOOOOOOOOOOOOD.....
..PPPDOOOOOOOOOOOODPPP..
.....DOKWOOOOOOKWOD.....
.....DOOOOOOOOOOOOD.....
..PPPDOROOOKKOOORODPPP..
.....DOOOOOOOOOOOOD.....
......DOOOOOOOOOOD......
.......DDOOOOOODD.......
......DOSOOOOOOSOD......
.....DOOWWWWWWOOOD.DD...
.....DOOWWWWWWOOODDOD...
......DOOOOOOOOOOD......
.......DOD....DOD.......
........................
........................
```

These grids are the dense-mode analogue of the §6 species files: same named frame
blocks, same face-slot substitution (eye/mouth pixels), same pattern mask (pattern
recolors interior `O` cells) and accessory anchors — one sprite format, two renderers.

**Fifty species are fully drawn in this format**, built exactly as the sprite plan
prescribes: body archetypes (sitting quadruped, round bird, dome, tentacled, squatting,
upright, wide, long, floating) × feature modules (ear/horn/antler variants, tails,
wings, shells, masks, beaks, manes) — the nine hand-originals plus 41 composed species,
each with `idle_1` + `idle_2` and a derived blink (`K→D` on eye rows). See
`sprites-pixel.txt` for the grids, `species50.py` for the composable generator, and
`gitagotchi-species-gallery.html` for all fifty animated in color. Body palettes derive
from the linguist hex (outline −35% lightness, light +60%, shade −12%; very dark colors
snap to a visible band), so every grid recolors to any user's top language.

**Full state sets, by derivation.** Every species carries the complete §8.3 frame list
(`sleep_1/2`, `eat_1..3`, `sick_1/2`, `celebrate_1/2`, `hibernate_1/2`), generated as
transforms of its two idle frames rather than drawn per species:

| State | Transform |
|---|---|
| sleep | eyes closed (`K→D` on eye rows) + 1px settle on frame 2 |
| eat | food bowl overlaid at rows 16–17 (always empty ground for all 50 bodies); pet dips 1px toward it; bowl full → half → empty across the 3 frames |
| sick | eyes closed + 1px droop + thermometer prop; renderer additionally draws the pet pale (SGR faint / desaturate) |
| celebrate | sparkle pixels at the stage corners + a 1px bounce |
| hibernate | the shared cocoon grid, tinted with the pet's own palette — one global sprite, since the pet is hidden inside |

Props (bowl, thermometer, sparkles) overlay only onto empty cells, so they always sit
*behind* the pet. The transforms live in `species50.py` (`make_states`) and are exactly
what the bash renderer computes at draw time — the state frames in `sprites-pixel.txt`
are the precomputed proof, not 550 hand-drawn originals.

**The motion library (procedural, universal).** Beyond state frames, ten named animations
are defined as pure grid-space transforms — shift, flip, shear (lean around the base),
squash/stretch (nearest-neighbor vertical resample anchored at the feet) — so every one
runs on every species with zero added art. Reference implementation + interactive demo:
`gitagotchi-animation-lab.html`.

| Animation | Recipe (over `idle_1`/`idle_2`) | Tick | State hook |
|---|---|---|---|
| breathe | squash .94→.90→.94 | 340ms | ambient, always on |
| wiggle | shear −1 · rest · shear +1 · rest | 200ms | mood ≥ 80 |
| waddle | shear±1 with 1px sidestep | 260ms | wander walk |
| bounce | up1 · up2+stretch1.07 · up1 · rest · squash .88 | 140ms | notification arrives |
| shiver | x±1 jitter + sweat drop | 110ms | health dropping, pre-sick |
| look-around | f1 · f2 · flip(f1) · flip(f2) | 800ms | curiosity high |
| jump-for-joy | double bounce, higher + sparkles | 150ms | celebrate upgrade |
| melt | eyes closed, squash .93→.86→.80→back | 480ms | sick idle |
| sleepy-sway | eyes closed, slow shear±1 + zzz | 600ms | sleep |
| love | plain idle + floating pixel hearts | 400ms | happiness > 80 |

Particles (hearts, sparkles, zzz, sweat) are 3×3-ish pixel stamps on a separate layer
above the pet, drifting 1 cell per tick — matching §2.3's float-up rules.

**Elder beard & wisdom glasses (procedural, universal).** The §6.7 elder additions in
pixel form — one rule, fifty chins (demo: `gitagotchi-elders.html`). The renderer finds
the face: eye row = first row with a `KW`/`WK` pair; mouth = first `KK` run *below* the
eye row (below-guard ignores dark caps like the ladybug's); else the beak's `PP` run;
else eye row + 2 centered between the eyes. From that anchor: mustache pixels at the
corners, then a beard tapering 8→6→4 wide (grand-elder ≥ 12y adds two forked rows).
Beard color is **fixed age-gray** (`#d8dee4`/`#9aa4ad`), never the linguist color, and
auto-darkens over light body cells (the penguin-belly rule); it paints *over* the body —
beards hang. Glasses (wisdom ≥ 60): a gray bridge across the eye row plus one frame
pixel outside each eye. Both stack with every state and motion, since they re-anchor
per frame.

---

## 10. Scenes — day/night & the four seasons

*(Demo: `gitagotchi-seasons.html` — interactive time × season matrix.)* The stage
dresses itself as a **pure function of the wall clock**: season from the local date
(`--south` flips hemispheres), day/night from the local hour (day = 07–19). Nothing is
stored, so the scene needs no new persistence — it honors the core invariant.

**Scene grammar — exactly three layers per mode:**

| Layer | Day | Night |
|---|---|---|
| Sky | pixel sun top-right + 1–2 clouds drifting 1 cell / 2 ticks | crescent moon + ~10 stars, twinkling in 3 phase groups |
| Weather | one particle type, falling 1 cell/tick with sway | same; summer swaps to **fireflies** (blinking, hovering) |
| Ground dressing | 4–5 stamps along the horizon | same, dimmed with the dashboard |

**Per season:** spring — falling petals · pixel flowers on the ground · green accent;
summer — grass tufts · no day particle · fireflies at night · gold accent; fall —
swaying leaves in 4 warm hues · leaf piles + a pumpkin · orange accent; winter — snow ·
snow line over the ground dots + mounds + a snowman with coal eyes · ice accent. The
panel border and stage background tint take the season hue (backgrounds stay within a
few steps of `#0d1117` so cozy/dense chrome never clashes).

**Pet crossovers (the two that matter, only two by design):** at night the pet sleeps
(closed eyes; dashboard dims one step, per §5.3) — and in winter, **snow accumulates on
the pet's crown**: the renderer finds each column's topmost pixel and caps those within
one row of the sprite's global top, so every species wears the snow on its own head,
ears, or gills. Scenes never touch stats — weather is scenery, not gameplay.

**v2 garden hook:** in spring, each ground flower can become one active day from the
contribution calendar (§ parked in the design doc) — scenery that is still derived,
never stored.

**Dense compare view**: two side-by-side panels, yours bordered in your linguist color,
theirs in theirs; pixel pets above 14-cell mirrored meters; `◂` in green marks the
higher row. Same rules as §5.7 (no winner line, health excluded).

**Dense state treatments**: sleeping dims the whole screen one step; sick shifts every
panel border to red and renders the pet pale; hibernation renders the cocoon and all
stats in ice-blue with `❄` prefixes. The state recolors the *frame*, not just the pet —
at btop density the border color is the fastest thing the eye catches.

### 9.3 Meters, sparklines, graph

- **Meters**: 18 gradient cells, red→amber→green along the *scale* (btop-style), filled
  to the value; the number is always printed and threshold-colored — color is never the
  only encoding (CVD-safe).
- **Sparklines**: each vitals row carries its last 10 refreshes as `▁▂▃▄▅▆▇█`, all in a
  single quiet blue — history is context, not identity, so it doesn't compete with the
  gradient.
- **Activity graph**: 60 days of events/day as block-eighth columns colored on the
  4-step GitHub contribution-green ramp; a dashed orange line marks *your* 90-day
  baseline; annotations mark rest gaps (`└ rest gap · 4d ┘`, ice-blue — celebrated, not
  shamed) and merges (`▲ #482 merged`).
- **Feed panel**: the liveness log with reason tags (`merge` green, `review` cyan,
  `mention` yellow, `medal` orange, `rest` ice) and the stat effect (`+18 hunger`) —
  it teaches the stat system by narrating it.

### 9.4 Dense-mode palette (roles, not decoration)

| Hex | ANSI-256 | Role |
|---|---|---|
| `#0d1117` | 233 | surface (GitHub dark — the pet lives where the data lives) |
| `#e6edf3` / `#8b949e` | 255 / 245 | ink / muted ink |
| linguist (e.g. `#dea584`) | nearest | pet + its panel border — the only large saturated area |
| `#3fb950` / `#d29922` / `#f85149` | 77 / 172 / 203 | meter gradient poles; good/warn/low |
| `#58a6ff` | 111 | friends panel, sparklines |
| `#39c5cf` | 80 | review scroll ⎘ |
| `#bc8cf2` | 140 | feed panel |
| `#79c0f2` | 117 | hibernation / frozen ❄ |
| `#0e4429→#39d353` | 22→41 | activity ramp (4 steps) |

Validated against the dark surface: all accents ≥ 3:1 contrast; the amber↔green adjacency
in the meter gradient is CVD-tight, which is why fill *length* and the printed value are
the primary encodings and color is redundant.
