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

# starving variant: zero merges (hunger 0) but everything else thriving, so the
# raw composite exceeds 60 and the misery cap visibly binds (plan.md §3.1)
cp "$OUT"/*.json "$OUT-starving/"
echo '{"total_count": 0, "items": []}' > "$OUT-starving/merged.json"
# ecstatic-tier feedback: the cap note only shows when it BINDS (raw > 60),
# so everything except hunger must genuinely thrive
echo '{"total_count": 30, "items": []}' > "$OUT-starving/approved.json"
echo '[]' > "$OUT-starving/stale.json"
{
  ev() { jq -n --arg t "$(iso "$1")" --arg ty "$2" --arg rn "$3" \
    '{type:$ty, created_at:$t, repo:{name:$rn}}'; }
  # three ≥6h gaps touching the last 24h → well rested; outbound-heavy → social
  ev 2 IssueCommentEvent mona/sandbox;   ev 9  PullRequestReviewEvent mona/sandbox
  ev 16 IssueCommentEvent defunkt/tools; ev 23 IssueCommentEvent ashtom/notes
  ev 40 IssueCommentEvent mona/sandbox;  ev 60 PullRequestReviewEvent defunkt/tools
  ev 80 IssueCommentEvent mona/sandbox;  ev 100 IssueCommentEvent defunkt/tools
  ev 120 IssueCommentEvent mona/sandbox; ev 150 PullRequestReviewEvent ashtom/notes
  ev 170 IssueCommentEvent mona/sandbox; ev 200 ForkEvent octotest/zigzag
  ev 240 IssueCommentEvent defunkt/tools; ev 280 IssueCommentEvent mona/sandbox
  ev 320 PushEvent octotest/cli
} | jq -s . > "$OUT-starving/events.json"
jq -n --arg s0 "$(isod 1)" --arg s1 "$(isod 3)" --arg s2 "$(isod 5)" \
      --arg s3 "$(isod 8)" --arg s4 "$(isod 11)" '[
  {starred_at:$s0,repo:{}},{starred_at:$s1,repo:{}},{starred_at:$s2,repo:{}},
  {starred_at:$s3,repo:{}},{starred_at:$s4,repo:{}}
]' > "$OUT-starving/starred.json"
# 20 of 21 days active (fitness ~94 — thriving, so only hunger drags)
{
  days=""
  for d in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19; do
    days+="{\"date\":\"$(isod $d | cut -dT -f1)\",\"contributionCount\":2},"
  done
  echo "{\"data\":{\"user\":{\"contributionsCollection\":{\"contributionCalendar\":{
    \"totalContributions\": 1240,
    \"weeks\":[{\"contributionDays\":[${days%,}]}]}}}}}"
} | jq . > "$OUT-starving/calendar.json"

echo "fixtures written to $OUT/ and $OUT-starving/"
