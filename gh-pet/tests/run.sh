#!/usr/bin/env bash
# Offline test suite: the pet is a pure function of recorded API data, so CI
# renders snapshots from fixtures and asserts on them (plan.md §9.1).
set -uo pipefail
cd "$(dirname "$0")"
ROOT=$(cd .. && pwd)

PASS=0 FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok  · $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL· $1"; }
assert_contains() { # haystack needle label
  if grep -qF -- "$2" <<<"$1"; then ok "$3"; else fail "$3 (missing: $2)"; fi
}

./make_fixtures.sh fixtures >/dev/null

export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8   # snapshots assert tier-B glyphs
# scene pin: the suite runs at a summer noon — the mockup-canonical stage —
# so the color fingerprints below never depend on WHEN the suite runs
# (day/night + seasons otherwise read the real wall clock, plan.md §11)
export GITAGOTCHI_PRETEND_HOUR=12 GITAGOTCHI_PRETEND_MONTH=7
export XDG_CACHE_HOME=$(mktemp -d)
trap 'rm -rf "$XDG_CACHE_HOME"' EXIT

echo "· snapshot from fixtures (well-fed pet)"
SNAP=$("$ROOT/gh-pet" --fixtures fixtures --snapshot --cozy 2>&1)
if [[ $? -ne 0 ]]; then fail "snapshot exits 0"; echo "$SNAP" | head -5; else ok "snapshot exits 0"; fi
assert_contains "$SNAP" "happiness" "dashboard renders happiness headline"
assert_contains "$SNAP" "hunger"    "core bars present"
assert_contains "$SNAP" "medals"    "medal shelf renders"
assert_contains "$SNAP" "PS³"       "Pull Shark ×3 tier on shelf"
assert_contains "$SNAP" "[f]riends" "footer is the menu"
assert_contains "$SNAP" "adult"     "life stage derived (est. 2019 → adult)"
LINE_COUNT=$(wc -l <<<"$SNAP")
if (( LINE_COUNT >= 19 )); then ok "full-height frame ($LINE_COUNT lines)"; else fail "frame too short ($LINE_COUNT)"; fi

echo "· identity is stable when the cache is deleted (plan.md §1)"
NAME1=$(grep -o '^┌─ [A-Z][a-z]*' <<<"$SNAP" | head -1)
rm -rf "$XDG_CACHE_HOME/gitagotchi"
SNAP2=$("$ROOT/gh-pet" --fixtures fixtures --snapshot --cozy 2>&1)
NAME2=$(grep -o '^┌─ [A-Z][a-z]*' <<<"$SNAP2" | head -1)
if [[ -n $NAME1 && $NAME1 == "$NAME2" ]]; then ok "same pet after cache wipe ($NAME1)"; else fail "identity drifted: '$NAME1' vs '$NAME2'"; fi
# the generator is FROZEN (util.sh): editing it renames every pet in the
# wild, so the exact mapping is pinned — id 3151702 must always be Lonisux
assert_contains "$SNAP2" "Lonisux" "name generator frozen: id 3151702 → Lonisux, forever"

echo "· misery cap (plan.md §3.1): starving pet cannot be happy"
rm -rf "$XDG_CACHE_HOME/gitagotchi"
SNAP3=$("$ROOT/gh-pet" --fixtures fixtures-starving --snapshot --cozy 2>&1)
assert_contains "$SNAP3" "happiness capped at 60" "insight explains the cap"
HVAL=$(awk '/happiness/{for(i=NF;i>0;i--) if($i ~ /^[0-9]+$/){print $i; exit}}' <<<"$SNAP3")
if [[ -n $HVAL ]] && (( HVAL <= 60 )); then ok "happiness ≤ 60 while starving (got $HVAL)"; else fail "cap not applied (got ${HVAL:-none})"; fi

echo "· tier A (--ascii) renders without unicode"
rm -rf "$XDG_CACHE_HOME/gitagotchi"
SNAP4=$("$ROOT/gh-pet" --fixtures fixtures --snapshot --cozy --ascii 2>&1)
if grep -q '█\|✉\|❤' <<<"$SNAP4"; then fail "tier A leaked unicode"; else ok "tier A stays pure ASCII in chrome"; fi
assert_contains "$SNAP4" "happiness" "tier A still renders the dashboard"

echo "· dense layout (default): five panels render at 80×24"
rm -rf "$XDG_CACHE_HOME/gitagotchi"
SNAP6=$("$ROOT/gh-pet" --fixtures fixtures --snapshot 2>&1)
assert_contains "$SNAP6" "vitals"   "vitals panel present"
assert_contains "$SNAP6" "feed"     "feed panel present"
assert_contains "$SNAP6" "activity · contributions/day" "activity graph present (calendar-sourced)"
assert_contains "$SNAP6" "friends"  "friends panel present"
assert_contains "$SNAP6" "▆"        "gradient meters render (padded cells)"
echo "· cleanliness mess: dirt piles up on the ground as CLEAN falls"
SNAPM=$(GITAGOTCHI_PRETEND_CLEAN=10 COLORTERM=truecolor GITAGOTCHI_SNAPSHOT_COLOR=1 "$ROOT/gh-pet" --fixtures fixtures --snapshot --dense 2>&1)
assert_contains "$SNAPM" "146;100;60" "filthy stage shows pixel poop (its brown)"
SNAPM2=$(GITAGOTCHI_PRETEND_CLEAN=95 COLORTERM=truecolor GITAGOTCHI_SNAPSHOT_COLOR=1 "$ROOT/gh-pet" --fixtures fixtures --snapshot --dense 2>&1)
if grep -qF "146;100;60" <<<"$SNAPM2"; then fail "spotless stage stays spotless"; else ok "spotless stage stays spotless"; fi
echo "· wisdom beard: high wisdom grows chin pixels, shade from created_at"
# the shade is identity: sha256("2019-03-14T09:00:00Z")[0] % 10 → platinum,
# pinned like the name — recoloring the table re-dyes every beard in the wild
SNAPB=$(GITAGOTCHI_PRETEND_WISDOM=95 COLORTERM=truecolor GITAGOTCHI_SNAPSHOT_COLOR=1 "$ROOT/gh-pet" --fixtures fixtures --snapshot --dense 2>&1)
assert_contains "$SNAPB" "226;208;160" "sage pet wears the beard in its own shade (platinum)"
SNAPB2=$(GITAGOTCHI_PRETEND_WISDOM=10 COLORTERM=truecolor GITAGOTCHI_SNAPSHOT_COLOR=1 "$ROOT/gh-pet" --fixtures fixtures --snapshot --dense 2>&1)
if grep -qF "226;208;160" <<<"$SNAPB2"; then fail "low wisdom stays clean-shaven"; else ok "low wisdom stays clean-shaven"; fi
echo "· curiosity props: the pixel book stack sits beside the pet"
SNAPBK=$(GITAGOTCHI_PRETEND_VIG=books COLORTERM=truecolor GITAGOTCHI_SNAPSHOT_COLOR=1 "$ROOT/gh-pet" --fixtures fixtures --snapshot --dense 2>&1)
assert_contains "$SNAPBK" "74;118;184" "book stack: the blue base book renders"
assert_contains "$SNAPBK" "154;111;196" "book pile: the wide purple bottom book renders (varied colors)"
SNAPBK2=$(COLORTERM=truecolor GITAGOTCHI_SNAPSHOT_COLOR=1 "$ROOT/gh-pet" --fixtures fixtures --snapshot --dense 2>&1)
if grep -qF "74;118;184" <<<"$SNAPBK2"; then fail "no vignette, no books"; else ok "no vignette, no books"; fi
echo "· review duty: the pixel spear stands at the pet's side"
# fixture OUTBOUND7=4 ≥ 3 → the spear shows by default; staged 0 hides it
assert_contains "$SNAPBK2" "200;204;212" "spear: silver head renders on review duty"
SNAPSP=$(GITAGOTCHI_PRETEND_OUTBOUND=0 COLORTERM=truecolor GITAGOTCHI_SNAPSHOT_COLOR=1 "$ROOT/gh-pet" --fixtures fixtures --snapshot --dense 2>&1)
if grep -qF "200;204;212" <<<"$SNAPSP"; then fail "off duty, no spear"; else ok "off duty, no spear"; fi
echo "· day/night + seasons (plan.md §11): the wall clock dresses the stage"
# night: 100×34 leaves two rows of open sky above a 9-row pet
SNAPNT=$(GITAGOTCHI_PRETEND_HOUR=23 GITAGOTCHI_SNAP_COLS=100 GITAGOTCHI_SNAP_LINES=34 \
  COLORTERM=truecolor GITAGOTCHI_SNAPSHOT_COLOR=1 "$ROOT/gh-pet" --fixtures fixtures --snapshot --dense 2>&1)
# the ornaments are PIXEL sprites now (pix_scene_register) — fingerprints
# are their palette rgb values, not glyphs
assert_contains "$SNAPNT" "242;234;208" "night: the pixel crescent rises (undimmed cream)"
assert_contains "$SNAPNT" "195;205;232" "night: a 4-point pixel sparkle in a clear lane"
assert_contains "$SNAPNT" "150;160;185" "night: star motes fill the open sky"
assert_contains "$SNAPNT" "205;214;235" "night: a bright mote among them"
assert_contains "$SNAPNT" "30;39;58"  "night: the ground dims to moonlight"
# the moonlit palette reaches the pixel letters: spear silver 200;204;212
# cools to 140;153;195 (moonlit = ×0.70 ×0.75 ×0.92)
assert_contains "$SNAPNT" "140;153;195" "night: the spear cools under moonlight"
if grep -qF "200;204;212" <<<"$SNAPNT"; then fail "night: no daylight silver after dark"; else ok "night: no daylight silver after dark"; fi
SNAPWN=$(GITAGOTCHI_PRETEND_MONTH=1 COLORTERM=truecolor GITAGOTCHI_SNAPSHOT_COLOR=1 "$ROOT/gh-pet" --fixtures fixtures --snapshot --dense 2>&1)
assert_contains "$SNAPWN" "188;215;242" "winter: pixel snow falls on the stage"
assert_contains "$SNAPWN" "96;108;128" "winter: frost settles on the ground"
SNAPSG=$(GITAGOTCHI_PRETEND_MONTH=4 COLORTERM=truecolor GITAGOTCHI_SNAPSHOT_COLOR=1 "$ROOT/gh-pet" --fixtures fixtures --snapshot --dense 2>&1)
assert_contains "$SNAPSG" "247;146;200" "spring: the pink pixel blossom roots on the floor"
SNAPAU=$(GITAGOTCHI_PRETEND_MONTH=10 COLORTERM=truecolor GITAGOTCHI_SNAPSHOT_COLOR=1 "$ROOT/gh-pet" --fixtures fixtures --snapshot --dense 2>&1)
assert_contains "$SNAPAU" "224;138;62" "autumn: pixel leaves drift in their own orange"
# the default frame (pinned summer noon) stays mockup-canonical: no scenery
if grep -q '242;234;208\|188;215;242\|247;146;200\|224;138;62' <<<"$SNAPBK2"; then fail "summer noon: the stage stays mockup-canonical"; else ok "summer noon: the stage stays mockup-canonical"; fi
echo "· expanded panels (gitagotchi-panels.html): s / g / f / e full views"
SNAP7=$("$ROOT/gh-pet" --fixtures fixtures --snapshot --dense --panel vitals 2>&1)
assert_contains "$SNAP7" "vitals · all 10"       "vitals: panel title"
assert_contains "$SNAP7" "how it's built"        "vitals: happiness composition panel"
assert_contains "$SNAP7" "misery cap"            "vitals: cap note present"
assert_contains "$SNAP7" "src: search"           "vitals: detail shows literal API source"
assert_contains "$SNAP7" "open your merged PRs on github ↗" "vitals: detail links out, labeled"
assert_contains "$SNAP7" "last 30 hours · derived hourly" "vitals: derived history caption"
assert_contains "$SNAP7" "health self"          "vitals: health carries the self tag"
SNAP7C=$("$ROOT/gh-pet" --fixtures fixtures-starving --snapshot --dense --panel vitals 2>&1)
assert_contains "$SNAP7C" "happiness capped at 60 — hunger is 0" "vitals: binding cap named in the note"
SNAP7L=$(GITAGOTCHI_SNAPSHOT_COLOR=1 "$ROOT/gh-pet" --fixtures fixtures --snapshot --dense --panel vitals 2>&1)
assert_contains "$SNAP7L" ']8;;https://github.com/octotest/cli/pull/482' "vitals: #PR in the why deep-links to the PR"
assert_contains "$SNAP7L" ']8;;https://github.com/issues?q=user%3Aoctotest' "vitals: labels hyperlink to their fix-it pages"
SNAP7T=$(GITAGOTCHI_CSEL=3 "$ROOT/gh-pet" --fixtures fixtures --snapshot --dense --panel vitals 2>&1)
assert_contains "$SNAP7T" "▸ consistency of activity" "vitals: tab tooltip defines the vital"

SNAP8=$("$ROOT/gh-pet" --fixtures fixtures --snapshot --dense --panel activity 2>&1)
assert_contains "$SNAP8" "[ 60d ]"               "activity: range tabs render"
assert_contains "$SNAP8" "▲ #482"                "activity: merges tick above the graph"
assert_contains "$SNAP8" "└ rest gap · "         "activity: rest gap celebrated below"
assert_contains "$SNAP8" "└ weekend ┘"           "activity: the weekend labeled as a feature"
assert_contains "$SNAP8" "avg events by weekday (90d)" "activity: weekday rhythm sub-panel"
assert_contains "$SNAP8" "contribution calendar" "activity: 12-week calendar sub-panel"
assert_contains "$SNAP8" "rhythm beats volume"   "activity: stance in the footer"
SNAP8Y=$(GITAGOTCHI_ACT_RANGE=365 "$ROOT/gh-pet" --fixtures fixtures --snapshot --dense --panel activity 2>&1)
assert_contains "$SNAP8Y" "-52w"                 "activity: 1y tab renders week axis"

SNAP9=$("$ROOT/gh-pet" --fixtures fixtures --snapshot --dense --panel feed 2>&1)
assert_contains "$SNAP9" "1 all"                 "feed: filter chips render"
assert_contains "$SNAP9" "7 security"            "feed: all seven chips present"
assert_contains "$SNAP9" "── today ──"           "feed: day grouping headers"
assert_contains "$SNAP9" "hunger"                "feed: entries narrate stat effects"
assert_contains "$SNAP9" " ate"                  "feed: merges narrate the pet eating"
assert_contains "$SNAP9" "→ pet slept while you did" "feed: rest gaps narrate the nap"
assert_contains "$SNAP9" "304s don't count"      "feed: poll note explains the budget"
assert_contains "$SNAP9" "search tier untouched (30/min cap)" "feed: budget notes the search cap"

SNAP10=$("$ROOT/gh-pet" --fixtures fixtures --snapshot --dense --panel friends 2>&1)
assert_contains "$SNAP10" "following · 3"        "friends: table counts follows"
assert_contains "$SNAP10" "❤ happy ▾"            "friends: sort column header"
assert_contains "$SNAP10" "mona"                 "friends: rows list logins"

echo "· dense compare view (gitagotchi-compare.html)"
SNAP11=$("$ROOT/gh-pet" compare mona --fixtures fixtures --snapshot 2>&1)
assert_contains "$SNAP11" "┤ compare ├"          "compare: one purple panel, embedded title"
assert_contains "$SNAP11" "vs"                   "compare: pets face off across the center"
assert_contains "$SNAP11" "since 2019"           "compare: friends-since is the younger account's est. year"
# relationship status from the summed COMMS_RAW bond ledgers; the shared
# fixture user.json makes both logins 'octotest', so the bond is 0 here —
# the real-data path (issue/PR authors, org repos included) is person-level
assert_contains "$SNAP11" "distant orbits"       "compare: relationship status in the vs cell"
assert_contains "$SNAP11" "est. 2019"            "compare: identity line under each pet"
assert_contains "$SNAP11" "◂"                    "compare: green marker on the higher side"
assert_contains "$SNAP11" "curiosity"            "compare: slow stats under the dashed rule"
assert_contains "$SNAP11" "health — private on both sides, by design" "compare: health absent by design"
assert_contains "$SNAP11" "last 14 days · events/day" "compare: dual activity mini-chart"
assert_contains "$SNAP11" "medal shelves · shared medals in green" "compare: medal shelves"
assert_contains "$SNAP11" "what the pets noticed" "compare: insights"
assert_contains "$SNAP11" "friendly rivalry, not a leaderboard" "compare: stance in the footer"
assert_contains "$SNAP11" "snapshot to stdout"   "compare: share key in the footer"
if ! grep -qF "health" <<<"$SNAP11" || ! grep -qE '(happy|hunger).*[▄#]' <<<"$SNAP11"; then
  fail "compare: mirrored bars render"
else
  ok "compare: mirrored bars render"
fi

echo "· friends lists scroll instead of overflowing (22 follows)"
MANYFIX=$(mktemp -d)
cp -R fixtures/. "$MANYFIX"
jq -n '[range(0;22) | {login: ("user\(.)")}]' > "$MANYFIX/following.json"
# expanded panel, short pane, cursor deep in the list: window + both markers
SNAP12=$(GITAGOTCHI_SNAP_COLS=100 GITAGOTCHI_SNAP_LINES=16 GITAGOTCHI_FSEL=14 \
  "$ROOT/gh-pet" --fixtures "$MANYFIX" --snapshot --panel friends 2>&1)
assert_contains "$SNAP12" "following · 22"  "friends panel: full count in the title"
assert_contains "$SNAP12" "↑ "              "friends panel: scrolled-past marker in the divider"
assert_contains "$SNAP12" "↓ "              "friends panel: more-below marker under the window"
assert_contains "$SNAP12" "▸"               "friends panel: the selected row scrolled into view"
# main screen card: viewport range hint in the header
SNAP13=$(GITAGOTCHI_SNAP_COLS=100 GITAGOTCHI_SNAP_LINES=34 GITAGOTCHI_FSEL=20 \
  "$ROOT/gh-pet" --fixtures "$MANYFIX" --snapshot --dense 2>&1)
assert_contains "$SNAP13" "↕ 21-"           "friends card: window followed the cursor to row 21"
assert_contains "$SNAP13" "/22"             "friends card: hint carries the full count"
rm -rf "$MANYFIX"

echo "· fetch: the merged-PR ball game"
SNAP14=$(COLORTERM=truecolor GITAGOTCHI_SNAPSHOT_COLOR=1 GITAGOTCHI_SNAP_COLS=100 GITAGOTCHI_SNAP_LINES=34 \
  GITAGOTCHI_FETCH_T=3 "$ROOT/gh-pet" --fixtures fixtures --snapshot --dense 2>&1)
assert_contains "$SNAP14" "224;72;59" "fetch: the red pixel ball rendered on the stage"
SNAP15=$(COLORTERM=truecolor GITAGOTCHI_SNAPSHOT_COLOR=1 GITAGOTCHI_SNAP_COLS=100 GITAGOTCHI_SNAP_LINES=34 \
  "$ROOT/gh-pet" --fixtures fixtures --snapshot --dense 2>&1)
if grep -qF "224;72;59" <<<"$SNAP15"; then
  fail "fetch: no ball outside the game"
else
  ok "fetch: no ball outside the game"
fi

echo "· badge: the pet as a self-contained SVG (plan.md §11)"
rm -rf "$XDG_CACHE_HOME/gitagotchi"
SVG1=$("$ROOT/gh-pet" badge --fixtures fixtures 2>&1)
if [[ $? -ne 0 ]]; then fail "badge exits 0"; else ok "badge exits 0"; fi
assert_contains "$SVG1" "<svg xmlns" "badge: emits svg"
assert_contains "$SVG1" "Lonisux"    "badge: the pet's name on the card"
assert_contains "$SVG1" "crispEdges" "badge: pixel rects stay crisp"
assert_contains "$SVG1" 'id="blink"' "badge: blink overlay on an awake pet"
# deterministic for a given state (no clocks, no RANDOM) — that's what lets
# the cron workflow commit-only-if-changed without churn
rm -rf "$XDG_CACHE_HOME/gitagotchi"
SVG2=$("$ROOT/gh-pet" badge --fixtures fixtures 2>&1)
if [[ "$SVG1" == "$SVG2" ]]; then ok "badge: deterministic across a cache wipe"; else fail "badge: output drifted between runs"; fi
SVGH=$(GITAGOTCHI_PRETEND_QUIET=35 "$ROOT/gh-pet" badge --fixtures fixtures 2>&1)
assert_contains "$SVGH" "hibernating" "badge: hibernation named on the card"
if grep -qF 'id="blink"' <<<"$SVGH"; then fail "badge: cocoons don't blink"; else ok "badge: cocoons don't blink"; fi

echo
echo "════ passed $PASS · failed $FAIL ════"
(( FAIL == 0 ))
