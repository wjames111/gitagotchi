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

# clock pin: the pet lives on the wall clock — it SLEEPS at night and the
# feed groups by local date. Derive at local noon wherever/whenever the
# suite runs by picking the TZ where it is 12:xx right now (00:30 UTC on a
# CI runner once put the whole suite to bed: no spear, no props, no badge
# blink, and "today" had become yesterday). POSIX sign: TZ=UTC-3 = UTC+3h.
_h=$(date -u +%H); _h=${_h#0}; _h=${_h:-0}
export TZ="UTC$(( _h - 12 ))"

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
# The cap only BINDS — and only says so — when the raw composite would clear 60,
# so the fixture has to be an elite pet with an empty belly. That premise is worth
# asserting on its own: if a reweight drags raw under 60 the pet is honestly
# miserable without the cap, the insight below vanishes, and the assert_contains
# alone would just report a missing string. Check the premise first so the failure
# names the cause.
_sargs=(-r --arg now "$(date +%s)" --arg login octotest)
for _f in user repos events merged approved changesreq reviewedby starred stale \
          alerts calendar notifications medals orgs following; do
  if [[ -s fixtures-starving/$_f.json ]]; then _sargs+=(--slurpfile "$_f" "fixtures-starving/$_f.json")
  else _sargs+=(--argjson "$_f" null); fi
done
RAWS=$(jq -n "${_sargs[@]}" -f "$ROOT/lib/stats.jq" 2>/dev/null \
       | sed -n "s/^HAPPY_RAW='\([0-9]*\)'.*/\1/p")
if [[ $RAWS =~ ^[0-9]+$ ]] && (( RAWS > 60 )); then
  ok "starving fixture still exercises the cap (raw $RAWS > 60)"
else
  fail "starving fixture no longer binds the cap (raw=${RAWS:-none}) — the cap tests below are testing nothing; make the pet elite again or move the cap test to a low-weight survival stat (see make_fixtures.sh)"
fi
SNAP3=$("$ROOT/gh-pet" --fixtures fixtures-starving --snapshot --cozy 2>&1)
assert_contains "$SNAP3" "happiness capped at 60" "insight explains the cap"
HVAL=$(awk '/happiness/{for(i=NF;i>0;i--) if($i ~ /^[0-9]+$/){print $i; exit}}' <<<"$SNAP3")
if [[ -n $HVAL ]] && (( HVAL <= 60 )); then ok "happiness ≤ 60 while starving (got $HVAL)"; else fail "cap not applied (got ${HVAL:-none})"; fi

echo "· the misery cap listens to SURVIVAL stats ONLY (plan.md §3.1): a pet with"
echo "  healthy survival stats but poor aspirational ones (curiosity/social/fitness/"
echo "  wisdom < 20) is NOT capped — guards the regression that flattened friends to 60"
_now=$(date +%s)
_merged=$(jq -n --argjson n "$_now" '{total_count:10, items:[range(0;10)|{number:., html_url:"h", pull_request:{merged_at:(($n-3600)|todate)}}]}')
_events=$(jq -n --argjson n "$_now" '[{type:"PushEvent",created_at:(($n-3600)|todate),repo:{name:"self/app"}},{type:"PushEvent",created_at:(($n-3600-25200)|todate),repo:{name:"self/app"}}]')
ASP=$(jq -n -r --arg now "$_now" --arg login self \
  --argjson user '[{"id":3151702,"login":"self","created_at":"2019-03-14T09:00:00Z"}]' \
  --argjson merged "[$_merged]" --argjson approved '[{"total_count":20}]' \
  --argjson alerts '[{"critical":0,"high":0,"moderate":0}]' --argjson events "[$_events]" \
  --argjson repos null --argjson changesreq null --argjson reviewedby null --argjson starred null \
  --argjson stale null --argjson calendar null --argjson notifications null --argjson medals null \
  --argjson orgs null --argjson following null -f "$ROOT/lib/stats.jq" 2>&1)
_hap=$(sed -n "s/^HAPPINESS='\([0-9]*\)'.*/\1/p" <<<"$ASP")
_cap=$(sed -n "s/^CAPPED_BY='\(.*\)'\$/\1/p" <<<"$ASP")
if [[ -n $_hap ]] && (( _hap > 60 )) && [[ -z $_cap ]]; then ok "aspirational stats never hard-cap (happiness $_hap > 60, uncapped)"; else fail "an aspirational stat capped a healthy pet (happiness=${_hap:-none} capped_by='$_cap')"; fi

echo "· you are never your own guest: GitHub logins are case-insensitive, so"
echo "  'gh-pet SELF' must still recognize self/app as its own — otherwise the"
echo "  owner of every repo you touch reads as a stranger and you turn up on your"
echo "  own stage as a visitor (and in your own outbound social score)"
_vev=$(jq -n --argjson n "$_now" '[
  {type:"IssueCommentEvent",created_at:(($n-600)|todate),repo:{name:"self/app"}},
  {type:"IssueCommentEvent",created_at:(($n-600)|todate),repo:{name:"mona/hello"},
   payload:{issue:{user:{login:"mona"}}}}]')
VIS=$(jq -n -r --arg now "$_now" --arg login SELF \
  --argjson user '[{"id":3151702,"login":"self","created_at":"2019-03-14T09:00:00Z"}]' \
  --argjson events "[$_vev]" \
  --argjson repos null --argjson merged null --argjson approved null --argjson changesreq null \
  --argjson reviewedby null --argjson starred null --argjson stale null --argjson alerts null \
  --argjson calendar null --argjson notifications null --argjson medals null \
  --argjson orgs null --argjson following null -f "$ROOT/lib/stats.jq" 2>&1)
_vis=$(sed -n "s/^VISITORS='\(.*\)'\$/\1/p" <<<"$VIS")
if [[ " $_vis " != *" self "* && " $_vis " != *" SELF "* ]]; then ok "self never appears in its own visitor list (VISITORS='$_vis')"; else fail "the pet is visiting itself (VISITORS='$_vis')"; fi
if [[ " $_vis " == *" mona "* ]]; then ok "a real last-hour interaction still drops by (mona)"; else fail "guest list lost a real visitor (VISITORS='$_vis')"; fi
_out=$(sed -n "s/^OUTBOUND7='\([0-9]*\)'\$/\1/p" <<<"$VIS")
if [[ $_out == 1 ]]; then ok "outbound social counts others' repos only, whatever the login's casing"; else fail "own-repo comments leaked into outbound social (OUTBOUND7=${_out:-none}, want 1)"; fi

echo "· unauthenticated / public-only path (plan.md §9.2): the pure function still"
echo "  derives when health is unknown and the contribution calendar is absent"
UARGS=(-r --arg now "$(date +%s)" --arg login octotest)
for f in user repos events merged approved changesreq reviewedby starred stale notifications medals orgs following; do
  if jq -e . "fixtures/$f.json" >/dev/null 2>&1; then UARGS+=(--slurpfile "$f" "fixtures/$f.json"); else UARGS+=(--argjson "$f" null); fi
done
UARGS+=(--argjson alerts null --argjson calendar null)
UNAUTH=$(jq -n "${UARGS[@]}" -f "$ROOT/lib/stats.jq" 2>&1)
assert_contains "$UNAUTH" "HEALTH=''"        "unauth: health is unknown (null), not a fake 0 or 100"
assert_contains "$UNAUTH" "ACT_SRC='events'" "unauth: fitness/activity fall back to the events stream"
_uhap=$(sed -n "s/^HAPPINESS='\([0-9]*\)'.*/\1/p" <<<"$UNAUTH")
if [[ $_uhap =~ ^[0-9]+$ ]] && (( _uhap >= 0 && _uhap <= 100 )); then ok "unauth: composite computes with the health weight redistributed (happiness $_uhap)"; else fail "unauth: happiness broke without health (got '${_uhap:-none}')"; fi

echo "· tier A (--ascii) renders without unicode"
rm -rf "$XDG_CACHE_HOME/gitagotchi"
SNAP4=$("$ROOT/gh-pet" --fixtures fixtures --snapshot --cozy --ascii 2>&1)
if grep -q '█\|✉\|❤' <<<"$SNAP4"; then fail "tier A leaked unicode"; else ok "tier A stays pure ASCII in chrome"; fi
assert_contains "$SNAP4" "happiness" "tier A still renders the dashboard"

echo "· drowsy (21–29 days quiet, plan.md): the pre-hibernation state — derived, and"
echo "  distinct from both sleep (< 21) and hibernation (≥ 30), which supersedes it"
_drow() { # quiet_days → stats.jq output
  local q=$1 ev
  ev=$(jq -n --argjson n "$_dnow" --argjson q "$q" '[{type:"PushEvent",created_at:(($n-$q*86400)|todate),repo:{name:"self/app"}}]')
  jq -n -r --arg now "$_dnow" --arg login self \
    --argjson user '[{"id":3151702,"login":"self","created_at":"2019-03-14T09:00:00Z"}]' --argjson events "[$ev]" \
    --argjson merged null --argjson repos null --argjson approved null --argjson changesreq null \
    --argjson reviewedby null --argjson starred null --argjson stale null --argjson alerts null \
    --argjson calendar null --argjson notifications null --argjson medals null --argjson orgs null \
    --argjson following null -f "$ROOT/lib/stats.jq" 2>&1
}
_dnow=$(date +%s)
DR25=$(_drow 25); DR33=$(_drow 33)
assert_contains "$DR25" "DROWSY='1'" "25 days quiet → drowsy"
assert_contains "$DR25" "HIB='0'"    "25 days quiet → not yet hibernating"
assert_contains "$DR33" "HIB='1'"    "33 days quiet → hibernating"
assert_contains "$DR33" "DROWSY='0'" "hibernation supersedes drowsy (≥ 30 days)"

echo "· degrade gracefully when achievements are unavailable (--no-scrape / no medals.json)"
NM=$(mktemp -d)/nomedals; mkdir -p "$NM"; cp fixtures/*.json "$NM/"; rm -f "$NM/medals.json"
rm -rf "$XDG_CACHE_HOME/gitagotchi"
SNAPNM=$("$ROOT/gh-pet" --fixtures "$NM" --snapshot --no-scrape 2>&1)
if grep -q "happiness" <<<"$SNAPNM"; then ok "--no-scrape / medals-absent pet still renders (no crash)"; else fail "medals-absent pet failed to render"; fi
if grep -qF "PS³" <<<"$SNAPNM"; then fail "medals shelf shown without a medals source"; else ok "no medals source → shelf quietly absent"; fi

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

# The beard hunts for the face — the mouth is "the first KK+ run below the
# eyes" — so it MUST read a pristine grid. An elder's spectacle rim (and a
# wired pet's dilated pupil) paint fresh K's directly under the eyes, and the
# hunt used to lock onto the left lens: the beard grew off the glasses, a row
# high and hanging past the side of the face. The fixture pet is an adult
# caterpillar, so no snapshot reaches this pairing — pin it directly.
# Drives the REAL pix_render, so the ordering of its transform calls is what's
# under test (asserting on pix_apply_beard alone would pass even if the anchor
# hunt drifted back below pix_apply_specs).
BEARDA=$(
  BASE_DIR="$ROOT/lib" SPRITE_DIR="$ROOT/sprites"
  source "$ROOT/lib/util.sh" 2>/dev/null; source "$ROOT/lib/pixel.sh" 2>/dev/null
  pix_db_load
  PIX_MODE=T PIX_CAPTURE=1 PIX_BEARD_RGB="226;208;160"
  #           id  frame  blink specs tired flip body mood sixp bigeye brows wag beard …
  for specs in 0 1; do
    pix_palette cat "#3178c6" 0
    pix_render cat idle_1 0 "$specs" 0 0 0 0 0 0 0 0 2 0 0 "" 0
    printf "specs$specs %s\n" "${PIXGRID[@]}"   # tag every row with its case
  done
)
# the mouth-anchored beard: the authored 8-wide run centred under the cat's
# chin, the body's D rim still intact on both flanks. The art is anamorphic
# (48x18, half-width pixels), so every authored width doubles — the run lands
# 16 wide. Asserted per-case: untagged, the adult's good row satisfies the grep
# and the elder's breakage sails through.
assert_contains "$BEARDA" "specs0 ..........DDDOOOBBBBBBBBBBBBBBBBOOSDDD.........." "beard hangs off the adult's mouth, centred"
assert_contains "$BEARDA" "specs1 ..........DDDOOOBBBBBBBBBBBBBBBBOOSDDD.........." "the elder's beard hangs in the very same place"
# the left-lens beard: shoved left, spilling out over the body outline. This
# used to grep a literal 24-wide row, which a 48-wide grid can never contain —
# the check had gone vacuous. Assert the geometry instead: the run sits centred
# in the body, so an anchor that drifted onto the lens shows up as a lopsided
# row whatever the art's width.
BROW=$(grep -F "specs1 " <<<"$BEARDA" | grep -m1 -F "BBBBBBBBBBBBBBBB" | sed 's/^specs1 //')
BLEAD=${BROW%%B*}; BTRAIL=${BROW##*B}
if [[ -n $BROW && ${#BLEAD} -eq ${#BTRAIL} ]]; then
  ok "beard ignores the elder's spectacle rim (not the left lens)"
else
  fail "beard off-centre: ${#BLEAD} cols left of it, ${#BTRAIL} right"
fi
# and the glasses still get drawn — the fix must not cost the elder its specs.
# Doubled from the authored DKKWKKKKKKKWKD, rim and bridge alike.
assert_contains "$BEARDA" "DDKKKKWWKKKKKKKKKKKKKKWWKKDD" "the bespectacled elder still wears its glasses"

# the beard is earned: a guest turning up must not shave the host. Everyone
# shrinks to half scale while hosting, and the shrink used to drop it.
SNAPH=$(GITAGOTCHI_PRETEND_WISDOM=95 GITAGOTCHI_PRETEND_VISITORS="octotest" \
  COLORTERM=truecolor GITAGOTCHI_SNAPSHOT_COLOR=1 \
  "$ROOT/gh-pet" --fixtures fixtures --snapshot --dense 2>&1)
assert_contains "$SNAPH" "226;208;160" "a hosting pet keeps the beard it earned (half scale)"
echo "· curiosity (≥75): the pet holds and reads a book (gitagotchi-reading.html)"
SNAPBK=$(GITAGOTCHI_PRETEND_VIG=books COLORTERM=truecolor GITAGOTCHI_SNAPSHOT_COLOR=1 "$ROOT/gh-pet" --fixtures fixtures --snapshot --dense 2>&1)
assert_contains "$SNAPBK" "47;95;176"   "reading: the held book's blue cover renders"
assert_contains "$SNAPBK" "244;240;226" "reading: the book's bright page renders"
SNAPBK2=$(COLORTERM=truecolor GITAGOTCHI_SNAPSHOT_COLOR=1 "$ROOT/gh-pet" --fixtures fixtures --snapshot --dense 2>&1)
if grep -qF "47;95;176" <<<"$SNAPBK2"; then fail "no vignette, no book"; else ok "no vignette, no book"; fi
echo "· review duty: the guardian-pose spear stands beside the pet"
# fixture OUTBOUND7=4 ≥ 3 → the spear shows by default; staged 0 hides it
assert_contains "$SNAPBK2" "205;214;224" "spear: steel blade renders on review duty"
assert_contains "$SNAPBK2" "138;90;43"   "spear: the wooden shaft renders"
SNAPSP=$(GITAGOTCHI_PRETEND_OUTBOUND=0 COLORTERM=truecolor GITAGOTCHI_SNAPSHOT_COLOR=1 "$ROOT/gh-pet" --fixtures fixtures --snapshot --dense 2>&1)
if grep -qF "205;214;224" <<<"$SNAPSP"; then fail "off duty, no spear"; else ok "off duty, no spear"; fi
echo "· day/night + seasons (plan.md §11): the wall clock dresses the stage"
# night: 100×34 leaves two rows of open sky above a 9-row pet
SNAPNT=$(GITAGOTCHI_PRETEND_HOUR=23 GITAGOTCHI_SNAP_COLS=100 GITAGOTCHI_SNAP_LINES=34 \
  COLORTERM=truecolor GITAGOTCHI_SNAPSHOT_COLOR=1 "$ROOT/gh-pet" --fixtures fixtures --snapshot --dense 2>&1)
# the ornaments are PIXEL sprites now (pix_scene_register, a 1:1 port of
# gitagotchi-seasons.html) — fingerprints are their palette rgb values. The
# whole night sky (moon + four-point stars + mote field) is one cream-blue
# HTML PAL.M #dce6f0 = 220;230;240
assert_contains "$SNAPNT" "220;230;240" "night: the crescent, stars and motes share the cream-blue sky"
assert_contains "$SNAPNT" "255;215;95" "summer night: fireflies blink over the lawn"
assert_contains "$SNAPNT" "30;39;58"  "night: the ground dims to moonlight"
# the moonlit palette reaches the pixel letters: spear steel 205;214;224
# cools to 143;160;206 (moonlit = ×0.70 ×0.75 ×0.92)
assert_contains "$SNAPNT" "143;160;206" "night: the spear steel cools under moonlight"
if grep -qF "205;214;224" <<<"$SNAPNT"; then fail "night: no daylight steel after dark"; else ok "night: no daylight steel after dark"; fi
SNAPWN=$(GITAGOTCHI_PRETEND_MONTH=1 COLORTERM=truecolor GITAGOTCHI_SNAPSHOT_COLOR=1 "$ROOT/gh-pet" --fixtures fixtures --snapshot --dense 2>&1)
assert_contains "$SNAPWN" "230;237;243" "winter: pixel snow (HTML S) sifts down the stage"
assert_contains "$SNAPWN" "34;39;46"   "winter: the snowman's coal eyes by the wall"
assert_contains "$SNAPWN" "96;108;128" "winter: frost settles on the ground"
SNAPSG=$(GITAGOTCHI_PRETEND_MONTH=4 COLORTERM=truecolor GITAGOTCHI_SNAPSHOT_COLOR=1 "$ROOT/gh-pet" --fixtures fixtures --snapshot --dense 2>&1)
assert_contains "$SNAPSG" "247;120;186" "spring: the pink pixel blossom (HTML F) roots on the floor"
SNAPAU=$(GITAGOTCHI_PRETEND_MONTH=10 COLORTERM=truecolor GITAGOTCHI_SNAPSHOT_COLOR=1 "$ROOT/gh-pet" --fixtures fixtures --snapshot --dense 2>&1)
assert_contains "$SNAPAU" "240;136;62" "autumn: leaves and piles drift in their own orange (HTML LEAFC)"
assert_contains "$SNAPAU" "232;118;44" "autumn: a pumpkin (HTML PUMPKIN) sits by the wall"
# a full port, so summer noon is no longer bare: the sun and grass dress it
# (deliberately diverging from gitachis.html's canonical dense card)
assert_contains "$SNAPBK2" "255;215;95" "summer noon: the sun (HTML SUN2) rides the sky"
assert_contains "$SNAPBK2" "46;160;67"  "summer noon: grass tufts (HTML GRASS) root the lawn"
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
# frame precedence must match anim_update (HIB > … > sick > … > sleep): a pet
# that is both unwell and quiet reads as sick, not merely asleep. Unit-tested
# on the extracted badge_frame so the precedence is pinned in isolation.
BF=$(
  source "$ROOT/lib/util.sh" 2>/dev/null; source "$ROOT/lib/badge.sh" 2>/dev/null
  declare -A B1=([HIB]=0 [SLEEPING]=1 [HEALTH]=30); badge_frame B1; echo "sicksleep $BADGE_FRAME $BADGE_FAINT $BADGE_BLINKABLE"
  declare -A B2=([HIB]=0 [SLEEPING]=1 [HEALTH]=95); badge_frame B2; echo "healthysleep $BADGE_FRAME"
  declare -A B3=([HIB]=1 [SLEEPING]=1 [HEALTH]=30); badge_frame B3; echo "hibsick $BADGE_FRAME"
  declare -A B4=([HIB]=0 [SLEEPING]=0 [HEALTH]=""); badge_frame B4; echo "unauth $BADGE_FRAME"
)
assert_contains "$BF" "sicksleep sick_1 1 0"  "badge: a sick, sleeping pet reads sick (sick precedes sleep, faint, no blink)"
assert_contains "$BF" "healthysleep sleep_1"  "badge: a healthy, sleeping pet reads asleep"
assert_contains "$BF" "hibsick hibernate_1"   "badge: hibernation still supersedes sick and sleep"
assert_contains "$BF" "unauth idle_1"         "badge: unknown (unauth) health never triggers the sick frame"

echo "· logins are case-insensitive (same_login, util.sh): the CLI arg and the"
echo "  PRETEND_* knobs carry whatever casing was typed, API payloads carry the"
echo "  canonical spelling — the jq side has its own twin of this rule"
SL=$(
  source "$ROOT/lib/util.sh" 2>/dev/null
  same_login WillJames willjames && echo "case-insensitive yes"
  same_login mona mona           && echo "identical yes"
  same_login mona defunkt        || echo "different no"
  same_login "" willjames        || echo "empty-left no"
  same_login willjames ""        || echo "empty-right no"
  same_login "" ""               || echo "both-empty no"
)
assert_contains "$SL" "case-insensitive yes" "same_login: WillJames is willjames"
assert_contains "$SL" "identical yes"        "same_login: a login matches itself"
assert_contains "$SL" "different no"         "same_login: distinct logins stay distinct"
assert_contains "$SL" "empty-left no"        "same_login: an unauthenticated ME matches nobody"
assert_contains "$SL" "empty-right no"       "same_login: an unset PRETEND_* knob matches nobody"
assert_contains "$SL" "both-empty no"        "same_login: empty is not everyone"

echo "· your own pet is Zeruko however you spell yourself (derive.sh): getting"
echo "  this wrong renders your own pet under a stranger's derived name — the"
echo "  same comparison decides SELF, which gates the authed fetch tier"
ZK=$(
  export XDG_CACHE_HOME=$(mktemp -d)
  SPRITE_DIR="$ROOT/sprites"; BASE_DIR="$ROOT"
  # the suite runs set -u, which this subshell inherits: load_state reads
  # ${#PIX_SPECIES[@]} and PIXNAME, so declare them empty (pixel.sh's job in
  # the app) and take the sprites.sh fallback path rather than die unbound
  declare -a PIX_SPECIES=(); declare -A PIXNAME=()
  source "$ROOT/lib/util.sh"; source "$ROOT/lib/sprites.sh"
  source "$ROOT/lib/fetch.sh"; source "$ROOT/lib/derive.sh"
  _mk() { mkdir -p "$CACHE_ROOT/$1"; printf 'ID=3151702\nLOGIN=%s\nCREATED=2019-03-14T09:00:00Z\n' "$1" > "$CACHE_ROOT/$1/state.env"; }
  _mk WillJames; _mk SomeoneElse
  FIXDIR=""
  ME=willjames; declare -A Z1; load_state Z1 WillJames;   echo "wrongcase ${Z1[NAME]}"
  ME=willjames; declare -A Z2; load_state Z2 SomeoneElse; echo "stranger ${Z2[NAME]}"
  ME="";        declare -A Z3; load_state Z3 WillJames;   echo "unauth ${Z3[NAME]}"
  rm -rf "$XDG_CACHE_HOME"
)
assert_contains "$ZK" "wrongcase Zeruko"  "your pet is Zeruko even when you type your login in the wrong case"
assert_contains "$ZK" "stranger Lonisux"  "a friend keeps their derived name (Zeruko is not handed out)"
assert_contains "$ZK" "unauth Lonisux"    "unauthenticated: an empty ME never claims a pet as yours"

echo "· state legality table (§8.4): the single source of truth for which"
echo "  visual layers may coexist — no sleeping-reader, no sick ball-batter,"
echo "  no egg throwing a ball (render.sh gate_expr / gate_props)"
GATES=$(
  source "$ROOT/lib/util.sh" 2>/dev/null; source "$ROOT/lib/render.sh" 2>/dev/null
  for f in idle_1 stretch sleep_1 sick_2 hibernate_1; do gate_expr "$f"; echo "expr $f $GATE_EXPR $GATE_BODY $GATE_BEARD"; done
  for s in idle eat sleep sick wake hib hatch; do gate_props "$s" adult; echo "props $s $GATE_PROPS $GATE_HOST"; done
  gate_props idle egg; echo "props eggidle $GATE_PROPS $GATE_HOST"
)
assert_contains "$GATES" "expr idle_1 1 1 1"      "gate_expr: idle keeps expression, silhouette, beard"
assert_contains "$GATES" "expr sleep_1 0 1 1"     "gate_expr: sleep sets down spear/book/expression (beard survives)"
assert_contains "$GATES" "expr stretch 0 1 1"     "gate_expr: the wake stretch drops expression — no mid-yawn wag/spear"
assert_contains "$GATES" "expr hibernate_1 0 0 0" "gate_expr: the cocoon hides expression, silhouette AND beard"
assert_contains "$GATES" "props idle 1 1"         "gate_props: idle welcomes floor props and guests"
assert_contains "$GATES" "props sleep 0 1"        "gate_props: no floor props while asleep (sleep yields to guests upstream)"
assert_contains "$GATES" "props sick 0 0"         "gate_props: a sick pet takes no props and no guests"
assert_contains "$GATES" "props eggidle 0 0"      "gate_props: an egg holds the whole stage — no ball, no party"

echo
echo "════ passed $PASS · failed $FAIL ════"
(( FAIL == 0 ))
