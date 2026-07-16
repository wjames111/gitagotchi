# gitagotchi · `gh pet`

*A terminal Tamagotchi whose entire life is derived from your GitHub account.*

```
┌─ Zeruko · axolotl · adult ───────────────── [✉ 2] [⎘ 1] ─┐
│                                             ╭ medals ──╮ │
│                 ▄▄            ▄▄            │ PS³ YOLO │ │
│              ▄████████████████▄             │ QD   GB  │ │
│           ▀▀▀██▐▌██████████▐▌██▀▀▀          ╰──────────╯ │
│              ▀████████████████▀                          │
│ ························································ │
│  “Merged #482 four hours ago — Zeruko is well fed.”      │
│  happiness ❤ ██████████████████░░░░░░ 78                 │
└ [f]riends [s]tats [r]efresh [?]help [q]uit ──── ✓ 12s ───┘
```

The pet's persistent state is a **pure function**: `pet_state = f(github_data, wall_clock)`.
Nothing is stored, nothing is sent anywhere — GitHub *is* the database. Delete the
cache and the same pet hatches again, anywhere.

## Install

**Homebrew** (macOS / Linux):

```sh
brew install wjames111/gitagotchi/gitagotchi
```

**Debian / Ubuntu** — grab the `.deb` from the [latest release](https://github.com/wjames111/gitagotchi/releases/latest):

```sh
sudo apt install ./gitagotchi_*_all.deb
```

**From source** — requires `bash ≥ 4`, `curl`, `jq` (macOS: `brew install bash jq`):

```sh
git clone https://github.com/wjames111/gitagotchi && cd gitagotchi/gh-pet
./gh-pet
```

Both packages install the CLI as `gh-pet` and pull in `jq`/`curl`.

## Run

```sh
gh-pet                      # your pet (auth via gh CLI, $GITHUB_TOKEN, or public-only)
gh-pet octocat              # anyone's pet from public data
gh-pet compare octocat      # side-by-side — friendly rivalry, not a leaderboard
gh-pet badge > pet.svg      # the pet as SVG, for embedding in a README
gh-pet --snapshot           # one plain-text frame to stdout (README/CI embedding)
gh-pet --ascii              # glyph tier A, pure ASCII
gh-pet --no-scrape          # skip the GitHub-achievements scrape
gh-pet --fixtures gh-pet/tests/fixtures   # fully offline, from recorded API data (source checkout)
```

Keys: `f` friends · `s` stat detail (every low bar links to the page that fixes it) ·
`g` activity graph · `e` feed log · `c` compare · `r` refresh · `d` dense ↔ cozy ·
`?` help · `Esc` back · `q` quit.

## Dense mode (btop-style)

On terminals ≥ 110×32 with truecolor, the **dense layout** is the default
(`--dense` / `--cozy` force it): five titled panels whose border color is their
identity — pet (linguist color) · vitals with 10-refresh sparklines and
red→amber→green gradient meters · a 60-day events/day graph with your dashed
90d baseline, rest-gap and merge annotations · a friends table with mini-meters
· a live feed log with reason tags and stat effects. Sparkline history is
*derived*, not stored: the same pure `f(github_data, wall_clock)` evaluated at
t−1h…t−10h. `j/k/↵/c` work directly on the friends table.

Each panel opens into a **full expanded view** via its hotkey (the key pinned in
its border): `s` vitals — all ten stats with trends, the selected one showing its
derived history, the human "why", its literal API query, and `↵` opening the
GitHub page that raises it, beside a happiness-composition panel that states the
misery-cap rule where it matters; `g` activity — `Tab` cycles 14d/60d/1y, with a
weekday-rhythm chart and a 12-week contribution calendar (quiet weekends render
as a feature, not a gap); `f` friends — the table plus a live preview of the
selected friend's pixel pet, stats, and medals from the 5-minute cache; `e` feed
— the day-grouped liveness log with `1-7` reason filters and the poll-budget
note. `--snapshot --panel vitals|activity|friends|feed` renders any of them
offline (`GITAGOTCHI_ACT_RANGE=14|60|365` picks the activity tab).

## How it renders

Render ladder: **truecolor half-block pixel art** (24×18 grids from
`sprites/sprites-pixel.txt`, 50 species, palettes recolored to your top language's
linguist color) → ANSI-256 half-block → pure-ASCII sprites (`sprites/*.sprite`).
`sprites/palettes.txt` is extracted from the species gallery
(`tools/extract-palettes.sh`) so the terminal matches the gallery exactly.

## The stats (all 0–100, all named to their GitHub source)

hunger ← merged PRs (7d, decays ½ every 2d) · energy ← rest gaps vs *your own*
baseline · mood ← approvals − changes-requested · fitness ← active days of last 14 ·
cleanliness ← stale issues/PRs on your top repos · curiosity ← stars/forks given,
new languages · social ← comments on others' repos · wisdom ← reviews given (slow,
~monotonic) · health ← Dependabot alerts (self only) · happiness ← weighted composite
with the **misery cap**: any stat < 20 caps happiness at 60.

No activity for 21 days → drowsy; 30 days → hibernation (stats freeze — vacations
are healthy, this is not a punishment).

## Badge — your pet in your profile README

`gh-pet badge` renders the pet as a self-contained SVG: each pixel of the
composed sprite becomes a `<rect>` (full authored fidelity — no half-block
squeeze), with the name, species, life stage and happiness meter on a card,
and a CSS blink that survives GitHub's image proxy. Every derived look comes
along — the beard, the spear, the six-pack, the hibernation cocoon.

Embed it with the workflow in [templates/pet-badge.yml](templates/pet-badge.yml)
(drop into your `<login>/<login>` profile repo):

```markdown
![my gitagotchi](pet.svg)
```

It runs on a 6-hour cron **plus** a push trigger — cron because the pet
changes even when GitHub doesn't (hunger decays, sleep and hibernation are
wall-clock), and there is no cross-repo "this user did something" trigger.
The SVG is deterministic for a given pet state, so the commit-if-changed
guard means the repo history only moves when the pet does.

## Development

```sh
tests/run.sh        # offline suite: renders snapshots from generated fixtures
```

The derive layer (`lib/stats.jq`) is one pure jq program over recorded API
responses — that's how CI tests a function of GitHub data without a network.
