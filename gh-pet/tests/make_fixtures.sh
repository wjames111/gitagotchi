#!/usr/bin/env bash
# Generate fresh-dated API fixtures so the pure derive layer can be tested
# offline (plan.md §9.1). Regenerate any time — dates are relative to now.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# default fixtures live beside the script (tests/); an explicit relative arg is
# resolved against the caller's CWD, not silently re-rooted under tests/.
if [[ -n ${1:-} ]]; then
  OUT=$1; [[ $OUT == /* ]] || OUT="$PWD/$OUT"
else
  OUT="$HERE/fixtures"
fi
cd "$HERE"
mkdir -p "$OUT" "$OUT-starving"

iso() { # hours-ago → ISO8601 UTC
  if date -u -v-1H +%Y >/dev/null 2>&1; then date -u -v-"$1"H +%Y-%m-%dT%H:%M:%SZ
  else date -u -d "$1 hours ago" +%Y-%m-%dT%H:%M:%SZ; fi
}
isod() { iso $(( $1 * 24 )); }

jq -n --arg created "2019-03-14T09:00:00Z" '{
  login: "octotest", id: 3151702, created_at: $created,
  bio: "makes small tools", hireable: true, site_admin: false,
  followers: 42, following: 23, public_repos: 6
}' > "$OUT/user.json"

jq -n --arg p0 "$(isod 1)" --arg p1 "$(isod 3)" --arg p2 "$(isod 9)" \
      --arg p3 "$(isod 30)" --arg p4 "$(isod 50)" --arg p5 "$(isod 200)" \
      --arg c_new "$(isod 20)" --arg c_old "$(isod 900)" '[
  {name:"cli",          full_name:"octotest/cli",          language:"Rust",       pushed_at:$p0, created_at:$c_old, fork:false},
  {name:"plugin-core",  full_name:"octotest/plugin-core",  language:"Rust",       pushed_at:$p1, created_at:$c_old, fork:false},
  {name:"webby",        full_name:"octotest/webby",        language:"TypeScript", pushed_at:$p2, created_at:$c_old, fork:false},
  {name:"dots",         full_name:"octotest/dots",         language:"Shell",      pushed_at:$p3, created_at:$c_old, fork:false},
  {name:"zigzag",       full_name:"octotest/zigzag",       language:"Zig",        pushed_at:$p4, created_at:$c_new, fork:false},
  {name:"old-rust",     full_name:"octotest/old-rust",     language:"Rust",       pushed_at:$p5, created_at:$c_old, fork:false}
]' > "$OUT/repos.json"

# events: latest 3h ago; an 8h overnight gap ends 3h ago (rest gap in last 24h);
# spread over 14 days, incl. outbound comments on others' repos + a fork
{
  ev() { jq -n --arg t "$(iso "$1")" --arg ty "$2" --arg rn "$3" \
    '{type:$ty, created_at:$t, repo:{name:$rn}}'; }
  ev 3   PushEvent octotest/cli
  ev 11  IssueCommentEvent mona/sandbox
  ev 12  PushEvent octotest/cli
  ev 26  PullRequestReviewEvent defunkt/tools
  ev 30  PushEvent octotest/plugin-core
  ev 50  PushEvent octotest/webby
  ev 55  IssueCommentEvent ashtom/notes
  ev 75  PushEvent octotest/cli
  ev 80  ForkEvent octotest/zigzag
  ev 100 PushEvent octotest/cli
  ev 122 PushEvent octotest/plugin-core
  ev 150 IssueCommentEvent mona/sandbox
  ev 170 PushEvent octotest/webby
  ev 200 PushEvent octotest/cli
  ev 240 PushEvent octotest/dots
  ev 264 PushEvent octotest/cli
  ev 290 PushEvent octotest/plugin-core
  ev 320 PushEvent octotest/cli
} | jq -s . > "$OUT/events.json"

jq -n --arg m0 "$(iso 4)" --arg m1 "$(isod 2)" --arg m2 "$(isod 5)" '{
  total_count: 3, items: [
    {number: 482, html_url: "https://github.com/octotest/cli/pull/482",
     repository_url: "https://api.github.com/repos/octotest/cli",
     pull_request: {merged_at: $m0}, closed_at: $m0},
    {number: 471, html_url: "https://github.com/octotest/cli/pull/471",
     repository_url: "https://api.github.com/repos/octotest/cli",
     pull_request: {merged_at: $m1}, closed_at: $m1},
    {number: 455, html_url: "https://github.com/octotest/plugin-core/pull/455",
     repository_url: "https://api.github.com/repos/octotest/plugin-core",
     pull_request: {merged_at: $m2}, closed_at: $m2}
]}' > "$OUT/merged.json"

echo '{"total_count": 2, "items": []}'  > "$OUT/approved.json"
echo '{"total_count": 0, "items": []}'  > "$OUT/changesreq.json"
echo '{"total_count": 25, "items": []}' > "$OUT/reviewedby.json"

jq -n --arg s0 "$(isod 2)" --arg s1 "$(isod 9)" --arg s2 "$(isod 40)" '[
  {starred_at: $s0, repo: {full_name: "mona/sandbox"}},
  {starred_at: $s1, repo: {full_name: "defunkt/tools"}},
  {starred_at: $s2, repo: {full_name: "ashtom/notes"}}
]' > "$OUT/starred.json"

jq -n --arg old "$(isod 60)" --arg old2 "$(isod 45)" --arg fresh "$(isod 2)" '[
  {updated_at: $old,  repository_url: "https://api.github.com/repos/octotest/plugin-core"},
  {updated_at: $old2, repository_url: "https://api.github.com/repos/octotest/plugin-core"},
  {updated_at: $old,  repository_url: "https://api.github.com/repos/octotest/cli",
   pull_request: {url: "x"}},
  {updated_at: $fresh, repository_url: "https://api.github.com/repos/octotest/cli"}
]' > "$OUT/stale.json"

echo '{"critical": 0, "high": 0, "moderate": 1}' > "$OUT/alerts.json"

# contribution calendar: 9 active days, all within the last 14 (well inside
# the 21-day fitness window) → ACTIVE21 = 9
{
  days=""
  for d in 0 1 2 4 5 7 8 11 13; do
    days+="{\"date\":\"$(isod $d | cut -dT -f1)\",\"contributionCount\":$((d % 5 + 1))},"
  done
  echo "{\"data\":{\"user\":{\"contributionsCollection\":{\"contributionCalendar\":{
    \"totalContributions\": 1240,
    \"weeks\":[{\"contributionDays\":[${days%,}]}]}}}}}"
} | jq . > "$OUT/calendar.json"

jq -n --arg t0 "$(iso 2)" --arg t1 "$(iso 15)" --arg t2 "$(iso 6)" '[
  {reason: "mention",          updated_at: $t0,
   subject: {title: "cli#91",  url: "https://api.github.com/repos/mona/sandbox/issues/91"}},
  {reason: "comment",          updated_at: $t1,
   subject: {title: "dots#4",  url: "https://api.github.com/repos/octotest/dots/issues/4"}},
  {reason: "review_requested", updated_at: $t2,
   subject: {title: "plugin-core#12",
    url: "https://api.github.com/repos/octotest/plugin-core/pulls/12"}}
]' > "$OUT/notifications.json"

jq -n '{ok: true, medals: [
  {name: "Pull Shark", tier: 3}, {name: "YOLO", tier: 1},
  {name: "Quickdraw", tier: 1},  {name: "Galaxy Brain", tier: 1},
  {name: "Starstruck", tier: 2}, {name: "Pair Extraordinaire", tier: 1}
]}' > "$OUT/medals.json"

echo '[]' > "$OUT/orgs.json"
jq -n '[{login:"mona"},{login:"defunkt"},{login:"ashtom"}]' > "$OUT/following.json"

# starving variant: zero merges (hunger 0) but everything else ELITE, so the raw
# composite still exceeds 60 and the misery cap visibly BINDS (plan.md §3.1).
#
# The bar for "elite" moved on 2026-07-16, when hunger's weight went 0.20 → 0.28.
# hunger=0 now costs 28 points off the top, so the other eight stats must average
# >83 to clear 60 (it was >75). The old merely-thriving fixture lands at raw 55
# under the new weights — the composite reports that pet's misery honestly and the
# cap never fires, which is the reweight working as intended but leaves the cap's
# binding path (and its insight string) untested. So this pet is now the literal
# subject of §3.1: shiny medals, empty belly.
#
# Every stat below is at or near its ceiling, and the ceilings are low in places:
# mood buckets top out at 92 (ecstatic), energy at 86. Raw lands at 66 — only 6
# clear of the cap, and that is close to the best a hunger=0 pet can do (the
# theoretical max is 72). If a future reweight raises hunger again there may be no
# elite pet left that the cap can bind, and this fixture stops being expressible;
# at that point the honest move is to test the cap through a low-weight survival
# stat (clean 5%, health 3%) instead, where it still does real work.
# tests/run.sh pins HAPPY_RAW > 60 so a drift reports as "raw fell to N", not as a
# missing string.
cp "$OUT"/*.json "$OUT-starving/"
echo '{"total_count": 0, "items": []}' > "$OUT-starving/merged.json"
echo '{"total_count": 30, "items": []}' > "$OUT-starving/approved.json"   # mood 92 (ecstatic, the bucket ceiling)
echo '[]' > "$OUT-starving/stale.json"                                    # clean 100
echo '{"critical": 0, "high": 0, "moderate": 0}' > "$OUT-starving/alerts.json"  # health 100
# social = 7·√outbound7 + min(following,20) — take the whole following cap
jq -n '[range(0;20) | {login: "friend\(.)"}]' > "$OUT-starving/following.json"
{
  ev() { jq -n --arg t "$(iso "$1")" --arg ty "$2" --arg rn "$3" \
    '{type:$ty, created_at:$t, repo:{name:$rn}}'; }
  # three ≥6h gaps touching the last 24h → rested: energy 58 + 8·min(gaps-1,2) = 74
  # (the wall below starts at 25h, so the 23h→25h gap is only 2h and doesn't count)
  ev 2 IssueCommentEvent mona/sandbox;   ev 9  PullRequestReviewEvent mona/sandbox
  ev 16 IssueCommentEvent defunkt/tools; ev 23 IssueCommentEvent ashtom/notes
  ev 40 ForkEvent octotest/zigzag        # forks14 → curiosity
  # A wall of outbound review/comment traffic from 25h back. Two things ride on
  # its SHAPE, not just its size:
  #   · social is sub-linear (7·√n), so it takes ~100 events to reach the 90s.
  #   · energy's +12 slow bonus needs rate14 < 0.6·baseline, i.e. span < 8.4d.
  #     Keeping the OLDEST event inside ~7d (the old fixture reached back 320h/13d)
  #     is what lifts energy 74 → 86, its ceiling. Don't stretch this tail.
  # All of it sits outside the last 24h, so the rest gaps above survive intact.
  # Eight distinct counterparts (repos30 lands on 9 with zigzag) — comfortably past
  # the min(repos30,8) cap on curiosity's everyday-signal term.
  _r=(mona/sandbox defunkt/tools ashtom/notes mona/labs defunkt/hub ashtom/kit mona/forge defunkt/lab)
  for _i in $(seq 0 99); do
    ev $(( 25 + _i + (_i / 8) * 3 )) IssueCommentEvent "${_r[_i % 8]}"
  done
} | jq -s . > "$OUT-starving/events.json"
# 7 stars in 14d (6 each) + forks + a new language + repos30 → curiosity 100
jq -n --arg s0 "$(isod 1)" --arg s1 "$(isod 2)" --arg s2 "$(isod 3)" \
      --arg s3 "$(isod 5)" --arg s4 "$(isod 8)" --arg s5 "$(isod 10)" \
      --arg s6 "$(isod 11)" '[
  {starred_at:$s0,repo:{}},{starred_at:$s1,repo:{}},{starred_at:$s2,repo:{}},
  {starred_at:$s3,repo:{}},{starred_at:$s4,repo:{}},{starred_at:$s5,repo:{}},
  {starred_at:$s6,repo:{}}
]' > "$OUT-starving/starred.json"
# 21 of 21 days active → fitness 100
{
  days=""
  for d in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    days+="{\"date\":\"$(isod $d | cut -dT -f1)\",\"contributionCount\":2},"
  done
  echo "{\"data\":{\"user\":{\"contributionsCollection\":{\"contributionCalendar\":{
    \"totalContributions\": 1240,
    \"weeks\":[{\"contributionDays\":[${days%,}]}]}}}}}"
} | jq . > "$OUT-starving/calendar.json"

echo "fixtures written to $OUT/ and $OUT-starving/"
