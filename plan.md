# Gitagotchi — Design Document

*A terminal Tamagotchi whose entire life is derived from your GitHub account.*

**Working title candidates:** `gitagotchi`, `octopet`, `tamagit` (command: `gh pet` as a gh extension)

---

## 1. Philosophy & core invariant

The pet's persistent state is a **pure function**:

```
pet_state = f(github_data, wall_clock)
```

The app never writes anything anywhere. There is no save file, no server, no sync protocol.
Any terminal on any machine running `f` against the same account renders the same pet —
GitHub *is* the database. This also makes friends free: a friend's pet is just
`f(their_public_data)`.

The **only** state allowed outside the function is session-local randomness — idle fidgets,
blink timing, which direction the pet wanders. It's allowed precisely because it doesn't
need to survive the session.

Two corollaries that keep the design honest:

1. **Every persistent trait must name its GitHub source.** If a feature can't point to an
   API field or a deterministic derivation of one, it can't persist.
2. **Caching is an optimization, never a source of truth.** A local cache (`~/.cache/gitagotchi/`)
   may hold API responses with ETags to save rate limit, but deleting it must never change
   the pet.

---

## 2. Identity & appearance (deterministic derivation)

All identity traits derive from the **numeric user ID** (`user.id`), not the username —
usernames can be changed, numeric IDs never change. The pet survives a rename with its
identity intact.

```
seed = sha256(user.id)          # 32 bytes; slice different bytes for different traits
```

| Trait | Derivation | Variety |
|---|---|---|
| **Species** | `seed[0] % 100` → index into a bundled list of ~100 ASCII creatures | 100 |
| **Name** | syllable generator seeded by `seed[1..6]` (see below) | ~1M combos |
| **Color** | official GitHub linguist hex color of the user's top language, mapped to nearest ANSI-256 color. Fallback: `seed[7]` → palette, for users with no repos | ~40 practical |
| **Pattern** | second-most-used language bucket → `solid / spots / stripes / patches` | 4 |
| **Accessory** | profile facts: bio set → bandana · `hireable: true` → bowtie · public org member → collar tag · site admin/Pro → tiny crown · none → bare | ~5 |
| **Life stage** | account age + lifetime contributions (§2.3) | 5 |

100 species × ~40 colors × 4 patterns × 5 accessories ≈ **80,000 visually distinct pets**,
every one reproducible from the account alone. The color rule is deliberately meaningful
rather than random: Rust devs get orange pets, Python devs blue ones — friends' pets
telegraph what they build.

### 2.1 Name generator

Names must feel organic, be pronounceable, rarely collide, and never change.

```
CONSONANTS = b d f g h j k l m n p r s t v w y z        (18)
VOWELS     = a e i o u                                   (5)

syllables  = 2 + (seed[1] % 2)                           # 2 or 3
for i in 1..syllables:
    name += CONSONANTS[seed[2i] % 18] + VOWELS[seed[2i+1] % 5]
capitalize(name)
```

Yields names like **Mopli-style** two-syllable ("Zeru", "Pabo", "Kilu") and three-syllable
("Zeruko", "Pabuni", "Moplika"). 90² ≈ 8k two-syllable + 90³ ≈ 729k three-syllable names;
collisions among a user's friend list are vanishingly rare, and a collision is charming
rather than broken (two pets can share a name, like real pets).

### 2.2 Face & posture are *not* identity

Eyes, mouth, ears-up/ears-down are rendered from **mood and energy** at draw time (§3).
Identity traits are the skeleton; stats are the animation.

### 2.3 Life stages

| Stage | Condition |
|---|---|
| 🥚 Egg | account < 7 days old |
| Hatchling | < 90 days **or** < 50 lifetime contributions |
| Kid | < 2 years or < 500 contributions |
| Adult | < 10 years |
| Elder | ≥ 10 years (gains a tiny ASCII beard; wisdom rendering bonus) |

Lifetime contributions come from the GraphQL `contributionsCollection` (public counts for
friends; includes private counts for yourself when authed).

---

## 3. The stat system

All stats are 0–100. Each names its GitHub signal, its decay behavior, and how the pet
shows it. Windows are rolling and computed at refresh time — no stored counters.

| # | Stat | GitHub signal | Formula sketch | Pet expression |
|---|---|---|---|---|
| 1 | **Hunger** (fullness) | Merged PRs, rolling 7 days | each merge contributes `14 · 0.5^(days_ago/2)`, clamp 0–100 — a full bowl takes a real multi-merge rhythm, but a weekend off doesn't empty it | eating animation when a new merge is detected live; whines at empty bowl after ~3 dry days |
| 2 | **Energy** | Gaps in the event stream | rested if ≥1 quiet gap of 6h+ in last 24h (base 58); drained by `events_per_day / personal_baseline` sustained > 1.75× | sleeps (`zZz`) during your inactivity; frazzled sprite + eye-bags when overworked — the anti-burnout mechanic |
| 3 | **Mood** | Net social feedback, last 7d | `stars_received + reactions_received + approvals − 2·changes_requested`, squashed into 5 buckets (ecstatic needs ≥ +25) | drives the face sprite: ecstatic / content / neutral / grumpy / miserable |
| 4 | **Fitness** | Contribution *consistency*, not volume | `100 · (active_days_of_last_21 / 21)^1.3` | fit pet stretches during idles; unfit pet grows a round ASCII belly |
| 5 | **Cleanliness** | Repo hygiene on your top-N recently-pushed repos | `100 − 12·(open issues idle >30d) − 6·(open PRs idle >30d)`, floor 0 | flies (`.·°`) buzz around a messy pet; triaging = grooming |
| 6 | **Curiosity** | Distinct repos touched (30d) + stars given + forks made (14d), new language touched (30d bonus) | `min(100, 5·min(repos,8) + 6·stars + 10·forks + 15·new_lang)` | toys scattered near the pet; bats a ball around |
| 7 | **Social** | Outbound comments/reviews on *others'* repos (7d) + friends followed | `min(100, 7·√outbound + min(following, 20))` — square-root curve, saturating takes ~200 comments | low social → pet stares out a little ASCII window |
| 8 | **Wisdom** | Reviews given + language diversity + account age | slow log-scale composite; effectively monotonic | earns tiny glasses at 60+; elder beard stacks |
| 9 | **Health** *(self only — needs auth)* | Open Dependabot/security alerts on your repos | `100 − 20·critical − 10·high − 5·moderate`, floor 0 | sick sprite with thermometer; fixing alerts is the medicine. Invisible on friends — sickness is private, by design |
| 10 | **Happiness** | Composite of 1–9 | see §3.1 | headline stat; hearts float up when > 80 |

### 3.1 Happiness formula

```
happiness = 0.20·hunger + 0.15·energy + 0.20·mood + 0.10·fitness
          + 0.10·cleanliness + 0.05·curiosity + 0.10·social
          + 0.05·wisdom + 0.05·health
```

**Misery cap:** if any *survival* stat (hunger, energy, mood, cleanliness, health) < 20,
happiness is capped at 60 — a starving pet cannot be happy no matter how shiny its medals.
This makes single-stat neglect visible instead of averaged away. The slow, aspirational
stats (curiosity, wisdom, fitness, social) weigh on the composite but never hard-cap it:
not starring a repo this fortnight isn't misery, and capping on them once flattened every
active friend to exactly 60.

For friends (no health data), health's weight redistributes proportionally across the rest.

### 3.2 Personal baseline, not absolute numbers

Energy and fitness compare against the *user's own* trailing 90-day baseline where noted.
A hobbyist committing twice a week and a maintainer committing 20×/day can both have a
thriving pet. The pet rewards rhythm, not raw output.

### 3.3 Hibernation (neglect handling)

No public events for **21 days** → pet gets drowsy (yawning idles, a small `💤?` hint).
At **30 days** → curls into an ASCII cocoon/burrow and hibernates. Stats freeze (no decay
while hibernating — this is explicitly *not* a punishment; vacations are healthy). First
event after return → wake-up stretch animation and stats resume computing from live data.

Because hibernation is derived (`days_since_last_event ≥ 30`), friends' pets show it too —
you can see at a glance which of your friends has gone quiet.

---

## 4. Medals

**Decision: scrape real GitHub Achievements.** There is no official API
([open community discussion](https://github.com/orgs/community/discussions/42605)), so:

- Fetch `https://github.com/{login}?tab=achievements` (public page, works for friends too).
- Parse achievement image `alt`/`src` attributes → medal list (Pull Shark, YOLO, Quickdraw,
  Galaxy Brain, Pair Extraordinaire, Starstruck, …) including tier (`x2`, `x3`, `x4`).
- Map each to a 1–2 char ASCII medal (`🦈`→`(P)`, or pure-ASCII `[PS]`-style tokens with
  color) rendered in a trophy row under the pet.

**Robustness rules** (scraping is brittle by nature):

- Cache parsed results 24h — achievements change rarely.
- Parse defensively; on any parse failure, render the trophy row as `medals: unavailable`
  and carry on. A markup change must never break the pet, only hide medals.
- Isolate all scraping in one function (`fetch_achievements()`) so fixes are one-line.
- Ship a `--no-scrape` flag for purists/CI.

---

## 5. Liveness: mail, review requests, and the 60-second heartbeat

The [REST notifications API](https://docs.github.com/en/rest/activity/notifications) is
built for exactly this pattern:

- It returns an **`X-Poll-Interval`** header (typically 60s) — obey it as the poll cadence.
- Poll with **`If-Modified-Since` / ETag**; a `304 Not Modified` response **does not count
  against the rate limit**. The steady-state cost of being "live" is nearly zero.

Notification `reason` fields map to pet behavior:

| Reason | Pet behavior | Link (OSC 8 hyperlink + printed URL fallback) |
|---|---|---|
| `mention`, `team_mention`, `comment`, `author` | envelope `[✉ 3]` appears beside the pet; pet perks ears | `https://github.com/notifications` |
| `review_requested` | pet sits up holding a little scroll `[⎘ PR]`; expectant face | the PR's `html_url` directly |
| `security_alert` | pet looks worried, thermometer pre-warning | the alert URL |

Messages are **never read or displayed** — the envelope is a count and a link. The pet is a
doorbell, not a mail client.

**Clickable links:** modern terminals (iTerm2, kitty, WezTerm, recent gnome-terminal,
Windows Terminal) support OSC 8 hyperlinks, so the envelope and scroll are genuinely
clickable. Older terminals get the URL printed in the footer.

### 5.1 Refresh tiers

Not everything needs a 60s cadence. Three tiers keep rate-limit cost trivial:

| Tier | What | Cadence | Cost/hr (authed, 5000/hr budget) |
|---|---|---|---|
| Fast | notifications, own events | 60s w/ ETag | ~0 when idle (304s are free), ≤120 when busy |
| Medium | stats recompute (search queries, repo hygiene) | 10 min | ~30 |
| Slow | identity, achievements scrape, friend list | 24h / on demand | ~5 |

Worst case sits comfortably under 200 requests/hour against a 5000/hour budget.
Note: the search API has its own 30 req/min limit — the merged-PR search lives in the
medium tier, well clear of it.

---

## 6. Friends

- Friend list = accounts you **follow** (`GET /users/{me}/following`).
- UI: press `f` → scrollable list, each row showing login + pet name + species glyph +
  happiness. Arrow keys + Enter → full-screen render of that friend's pet.
- A friend's pet is computed by the *same* `f()` from public data with your token
  (5000/hr applies; their data is public, your auth just pays for the requests):
  public events, public repos, followers, GraphQL public contribution calendar,
  scraped public achievements.
- What you *can't* see on a friend: health (Dependabot is private), private contributions.
  Their pet is the public face of their account — which is exactly the right semantic.
- Friend renders are cached 5 minutes; browsing 20 friends costs ~60–80 requests, once.

Side-by-side compare (`c` on a friend): your pet and theirs on one screen with stat bars
paired. Cheap to build, very shareable.

---

## 7. GitHub API surface (complete mapping)

| Data | Endpoint | Auth needed | Tier |
|---|---|---|---|
| Identity, user ID, bio, hireable | `GET /users/{login}` | no | slow |
| Own private profile | `GET /user` | yes | slow |
| Event stream (activity, gaps) | `GET /users/{login}/events` (ETag) | no (public) / yes (incl. private) | fast |
| Merged PRs (hunger) | `GET /search/issues?q=is:pr author:{login} is:merged merged:>{date}` | recommended | medium |
| Reviews given (wisdom, social) | `GET /search/issues?q=is:pr reviewed-by:{login} updated:>{date}` | recommended | medium |
| Stars received (mood) | `GET /users/{login}/repos` → sum recent `stargazers_count` deltas via events | no | medium |
| Stars given (curiosity) | `GET /users/{login}/starred?sort=created` | no | medium |
| Repo hygiene (cleanliness) | issues/PRs on top-5 recently-pushed own repos | no | medium |
| Languages (color, pattern, wisdom) | `GET /users/{login}/repos` → `language` fields (weighted by repo pushes) | no | slow |
| Contribution calendar (fitness, life stage) | GraphQL `contributionsCollection` | yes (GraphQL always needs a token; public data of friends OK) | medium |
| Followers/following | `GET /users/{login}/followers`, `/following` | no | slow |
| Notifications (mail, review requests) | `GET /notifications` (X-Poll-Interval, ETag) | yes — self only | fast |
| Security alerts (health) | `GET /repos/{o}/{r}/dependabot/alerts` | yes — self only | medium |
| Achievements (medals) | scrape `github.com/{login}?tab=achievements` | no | slow |

---

## 8. Rendering & animation

### 8.1 Screen

```
┌─ Zeruko ─ the Axolotl ── lvl: Adult ──────────────┐
│                                      [✉ 2] [⎘ PR] │
│                 (spots pattern,                   │
│      ^..^       linguist-orange,      medals:     │
│     (o․o)~      bowtie accessory)     [PS][YOLO]  │
│      ~~~                                          │
│                                                   │
│  food  ██████████░░░░  71   mood   ████████░░ 80  │
│  energy████░░░░░░░░░░  34   social ██████░░░░ 60  │
│  clean ████████████░░  85   happy  ████████░░ 78  │
│                                                   │
└─ [f]riends  [c]ompare  [r]efresh  [q]uit ─────────┘
```

v1 scene is **minimal by decision**: pet + bars + indicators. (v2: contribution-graph
garden behind the pet, real-date seasons — parked, see §11.)

### 8.2 Terminal mechanics

- Alternate screen buffer (`tput smcup`/`rmcup`), hidden cursor, restore on exit via `trap`.
- Redraw loop at **4 fps** (`sleep 0.25`) — Tamagotchis were never smooth; chunky is the charm.
- `SIGWINCH` trap → re-layout on resize; minimum 60×20, graceful "window too small" card.
- Input: `read -rsn1` with escape-sequence decoding for arrows. All navigation is
  keyboard; the only "clicks" are OSC 8 hyperlinks, which the terminal handles natively.

### 8.3 Sprites

- `sprites/` directory bundled with the program: 100 species files, plain text.
- Each species file holds named frame blocks: `idle_1`, `idle_2`, `sleep_1`, `sleep_2`,
  `eat_1..3`, `sick`, `hibernate`, `celebrate`. A tiny bash parser slices blocks by marker
  lines. Species can share a template skeleton (~10 body archetypes × head/tail/ear variants
  = 100 without hand-drawing 100 from scratch).
- Layered composition at draw time: base frame → pattern overlay chars (`•` spots / `≋`
  stripes) → accessory → face (from mood) → color via ANSI 256.

### 8.4 Animation states (priority order)

1. `hibernating` (cocoon, slow breathing)
2. `sick` (thermometer, droopy)
3. `sleeping` (during detected inactivity gap — `zZz` drift)
4. `eating` (triggered live when a poll detects a newly merged PR — the payoff moment)
5. `celebrating` (new medal / new follower burst, hearts)
6. `idle` (default: blink, tail flick, wander a few columns, stretch if fit, belly-scratch
   if unfit — sequenced by session-local randomness, the one legal non-derived state)

---

## 9. Stack, auth & distribution

### 9.1 Stack: bash core

- **bash ≥ 4 + curl + jq + tput/ANSI.** No compile step, hackable by its own audience,
  packageable everywhere (precedent: neofetch lived happily in brew/apt as a big bash script).
- Structure: `lib/fetch.sh` (curl + ETag cache), `lib/derive.sh` (jq → `state.json`),
  `lib/render.sh` (frame loop), `lib/input.sh`, `sprites/`.
- The derive layer is one honking jq program per tier — testable offline against recorded
  API fixtures (`tests/fixtures/*.json`), which is how CI tests a pure function of API data.

### 9.2 Auth

Resolution order:

1. `gh auth token` if gh CLI is installed and logged in (zero-setup path)
2. `$GITHUB_TOKEN` / `$GH_TOKEN` env var
3. Unauthenticated fallback: pet renders from public data only, no notifications, with a
   one-line hint that logging in unlocks mail/health/private contributions
   (60 req/hr unauthenticated — degrade refresh to 10 min)

Scopes needed: `notifications`, `repo` (for Dependabot alerts on private repos), `read:user`.

### 9.3 Distribution — both from day one (decision)

Same bash core, two thin entry points:

| Channel | Install | Notes |
|---|---|---|
| **gh extension** | `gh extension install {you}/gh-pet` → `gh pet` | repo named `gh-pet` with executable `gh-pet` at root; auth inherited from gh automatically |
| **Homebrew** | `brew install {tap}/gitagotchi` | formula installs script + sprites to `libexec`, symlinks bin |
| **apt** | `.deb` attached to GitHub Releases (+ optional PPA later) | `dpkg -i` path first; PPA once stable |

The gh-extension repo *is* the source of truth; brew formula and deb build from its tagged
releases in CI.

---

## 10. Build plan

| Phase | Deliverable | Scope |
|---|---|---|
| **0 — Sprite spike** (weekend) | `./pet.sh fixtures/user.json` renders one animated pet | frame loop, sprite parser, layering, 3 species, no network |
| **1 — Real data, static** | `gh pet {login}` renders any user's pet once | identity derivation, name generator, all stats from live API, happiness formula |
| **2 — Alive** | the live loop | 60s notification polling, ETag caching, eating-on-merge, sleeping, mail envelope, review-request scroll, OSC 8 links |
| **3 — Friends** | `f` key | following list, friend render from public data, compare view |
| **4 — Ship** | v1.0 | achievements scraping (+ graceful failure), hibernation, 100 species, packaging: gh extension + brew formula + deb, README with pet screenshots |

Each phase is independently demo-able — phase 0 is already a fun tweet.

## 11. Parked for v2

- Contribution-graph **garden** scenery behind the pet (active days → flowers).
  ~~Real-date seasons and day/night from local clock~~ — SHIPPED: the dense stage
  reads the wall clock (`scene_calc`, util.sh). Night (20:00–05:59) raises a
  pixel crescent moon, two 4-point pixel sparkles and a half-block mote field,
  and cools the whole pixel palette (`PIX_NIGHT` in `pix_palette`'s cache key);
  winter drops pixel snowflakes, spring roots pixel blossoms on the floor,
  autumn sheds pixel leaves (sprites in `pix_scene_register`, drawn through
  `scene_blit`'s obstacle ledger so weather passes behind the cast); the
  ground line wears the season. A summer noon renders the mockup-canonical
  frame — tests pin that. Knobs: `GITAGOTCHI_PRETEND_HOUR`,
  `GITAGOTCHI_PRETEND_MONTH`, `GITAGOTCHI_HEMI=S`, `--demo night|winter|spring|autumn`.
- Breeding/eggs: a repo with two co-authors hatches a guest egg? (needs a persistence story
  that stays within the derive-from-GitHub invariant — fun puzzle).
- `gh pet badge` → render your pet as SVG for README embedding.
- Org pets: `f(org_account)` works out of the box since orgs are accounts.

## 12. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Achievements scraping breaks on markup change | isolated parser, 24h cache, degrade to "medals unavailable", never crash (§4) |
| Search API's separate 30 req/min limit | search calls only in the 10-min medium tier |
| Unauthenticated users hit 60 req/hr | degraded 10-min refresh mode + nudge to `gh auth login` |
| bash portability (macOS ships bash 3.2) | require bash ≥ 4 via brew dependency; gh extension declares it; test on macOS/Linux CI matrix |
| Very active orgs/users → huge event pages | events endpoint is paginated; cap at 300 events (API's own window) — signals are all recent-window anyway |
| GraphQL requires a token even for public data | only the contribution calendar needs GraphQL; unauthenticated mode approximates fitness from the public events stream instead |

---

*Sources: [GitHub notifications REST API](https://docs.github.com/en/rest/activity/notifications) (X-Poll-Interval, 304-not-counted polling), [community discussion on the missing Achievements API](https://github.com/orgs/community/discussions/42605).*
