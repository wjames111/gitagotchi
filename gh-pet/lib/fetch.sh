# gitagotchi — lib/fetch.sh
# curl + ETag cache layer. Caching is an optimization, never a source of truth
# (plan.md §1): deleting ~/.cache/gitagotchi must never change the pet.
# Tiers (plan.md §5.1): fast 60s (ETag/304s are free) · medium 10 min · slow 24h.

CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/gitagotchi"
NETDIR="$CACHE_ROOT/.net"
API="https://api.github.com"

TTL_FAST=60 TTL_MEDIUM=600 TTL_SLOW=86400   # medium = 10 min (plan.md §5.1): keeps search calls well under the 30 req/min secondary limit
TTL_FRIEND=300   # friend renders cached 5 minutes (plan.md §6)

# ── auth resolution (plan.md §9.2): gh → env → unauthenticated ──────────────
TOKEN="" AUTH_MODE="none"
auth_init() {
  if [[ -n ${GITHUB_TOKEN:-} ]]; then TOKEN=$GITHUB_TOKEN AUTH_MODE=env
  elif [[ -n ${GH_TOKEN:-} ]]; then TOKEN=$GH_TOKEN AUTH_MODE=env
  elif have gh && TOKEN=$(gh auth token 2>/dev/null) && [[ -n $TOKEN ]]; then AUTH_MODE=gh
  else TOKEN="" AUTH_MODE=none
  fi
  if [[ $AUTH_MODE == none ]]; then
    TTL_FAST=600   # unauthenticated: degrade refresh to 10 min (plan.md §9.2)
  fi
  mkdir -p "$NETDIR"
}

mtime() {
  if stat -f %m "$1" >/dev/null 2>&1; then stat -f %m "$1"; else stat -c %Y "$1"; fi
}

date_ago() { # days → YYYY-MM-DD (UTC)
  if date -u -v-1d +%Y >/dev/null 2>&1; then date -u -v-"$1"d +%Y-%m-%d
  else date -u -d "$1 days ago" +%Y-%m-%d; fi
}

net_ok() { # $1 = header file
  date +%s > "$NETDIR/last_ok"
  echo ok > "$NETDIR/status"
  rm -f "$NETDIR/retry_at"
  local rem
  # tail -1: a header file can hold several response blocks (redirect hops,
  # informational responses) — concatenating their digits once rendered the
  # header as "api -43929394/5000". Only the final response's value is true.
  rem=$(grep -i '^x-ratelimit-remaining:' "$1" 2>/dev/null | tail -1 | tr -dc '0-9')
  [[ -n $rem ]] && (( rem <= 100000 )) && echo "$rem" > "$NETDIR/api_remaining"
}
net_fail() {
  local st=retry now; now=$(date +%s)
  local last=0; [[ -f $NETDIR/last_ok ]] && last=$(cat "$NETDIR/last_ok")
  (( now - last > 180 )) && st=offline
  echo "$st" > "$NETDIR/status"
  echo $((now + 40)) > "$NETDIR/retry_at"
}

# gapi login name ttl url [accept] — fetch into $CACHE_ROOT/$login/$name.json
gapi() {
  local login=$1 name=$2 ttl=$3 url=$4 accept=${5:-application/vnd.github+json}
  # An empty login collapses $CACHE_ROOT/$login to $CACHE_ROOT/ and scatters
  # api json across the cache root instead of into a pet's directory — which is
  # where the stray alerts.json/stale.json at the top level came from. Every
  # write below is keyed off $dir, so refuse once, here.
  [[ -n $login ]] || return 1
  local dir="$CACHE_ROOT/$login"; mkdir -p "$dir"
  local body="$dir/$name.json" etagf="$dir/$name.etag"

  # fixtures mode: pure function of recorded API data — no network at all
  if [[ -n ${FIXDIR:-} ]]; then
    [[ -r "$FIXDIR/$name.json" ]] && cp "$FIXDIR/$name.json" "$body"
    return 0
  fi

  if [[ -f $body ]]; then
    local age=$(( $(date +%s) - $(mtime "$body") ))
    (( age < ttl )) && return 0
  fi
  # back off while a retry window is open
  if [[ -f $NETDIR/retry_at ]] && (( $(date +%s) < $(cat "$NETDIR/retry_at") )); then
    return 1
  fi

  local -a hdrs=(-H "Accept: $accept" -H "X-GitHub-Api-Version: 2022-11-28")
  [[ -n $TOKEN ]] && hdrs+=(-H "Authorization: Bearer $TOKEN")
  if [[ -f $etagf && -f $body ]]; then hdrs+=(-H "If-None-Match: $(cat "$etagf")"); fi

  local tmp="$dir/.$name.tmp" hf="$dir/.$name.hdr" code
  code=$(curl -sS --max-time 15 "${hdrs[@]}" -D "$hf" -o "$tmp" -w '%{http_code}' "$url" 2>/dev/null) || code=000
  case $code in
    200)
      mv "$tmp" "$body"
      grep -i '^etag:' "$hf" | head -1 | tr -d '\r' | sed 's/^[Ee][Tt][Aa][Gg]: *//' > "$etagf"
      net_ok "$hf"
      if [[ $name == notifications ]]; then
        local pi; pi=$(grep -i '^x-poll-interval:' "$hf" | tr -dc '0-9')
        [[ -n $pi ]] && echo "$pi" > "$dir/poll_interval"
      fi
      ;;
    304) touch "$body"; net_ok "$hf" ;;
    *)   # optional endpoints (GAPI_SOFT=1) may 403/404 by design — e.g.
         # Dependabot alerts on repos without them; never trip the breaker
         rm -f "$tmp"
         [[ ${GAPI_SOFT:-0} == 1 ]] || net_fail
         return 1 ;;
  esac
}

search_q() { # raw query → encoded
  printf '%s' "$1" | sed 's/ /+/g; s/:/%3A/g; s/>/%3E/g'
}

# GraphQL contribution calendar (plan.md §7 — token required; public data of friends OK)
gql_calendar() { # login ttl
  local login=$1 ttl=$2; local dir="$CACHE_ROOT/$login"; mkdir -p "$dir"
  local body="$dir/calendar.json"
  # fixtures are hermetic: they load whether or not a token exists — the
  # token gate below is for the network, and it must come after this (an
  # unauthenticated machine once skipped the fixture calendar here, so CI
  # derived events-sourced stats while every authed laptop passed)
  if [[ -n ${FIXDIR:-} ]]; then
    [[ -r "$FIXDIR/calendar.json" ]] && cp "$FIXDIR/calendar.json" "$body"; return 0
  fi
  [[ -z $TOKEN ]] && return 0
  if [[ -f $body ]]; then
    local age=$(( $(date +%s) - $(mtime "$body") ))
    (( age < ttl )) && return 0
  fi
  # A GraphQL failure is HTTP 200 with `data.user: null` + errors[], so the test
  # for "did this work" has to be the CALENDAR, not `.data` — that only checked
  # the envelope, and happily cached an error body, which then read as a real
  # calendar full of zeroes (a 2013 account came out a hatchling with fitness 0).
  local tmp="$dir/.calendar.tmp"
  _cal_try() { # query_json → 0 if the response carries an actual calendar
    curl -sS --max-time 15 -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
      -d "$1" -o "$tmp" "$API/graphql" 2>/dev/null || return 1
    jq -e '.data.user.contributionsCollection.contributionCalendar' "$tmp" >/dev/null 2>&1
  }
  local q='query($login:String!){user(login:$login){contributionsCollection{contributionCalendar{totalContributions weeks{contributionDays{date contributionCount}}}}}}'
  if _cal_try "$(jq -n --arg q "$q" --arg l "$login" '{query:$q, variables:{login:$l}}')"; then
    mv "$tmp" "$body"; unset -f _cal_try; return 0
  fi
  # Busy accounts (canac, 13 years and thousands of contributions) get
  # RESOURCE_LIMITS_EXCEEDED on `weeks` — GitHub refuses to walk a whole year of
  # them, forever, so this is not a retry-and-hope case. Ask again from a 90-day
  # mark: same shape, and it answers. `from` alone spans from→+1y (the tail is
  # future zeros), so the last 21 days for fitness and 60 for the graph are all
  # present; totalContributions then counts 90 days rather than a year, which
  # reads a heavy account LOWER than a light one whose full query worked. It
  # still clears the stage thresholds by a mile, and losing 90 days of history
  # beats reporting zero.
  local from; from=$(date -u -v-90d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '90 days ago' +%Y-%m-%dT%H:%M:%SZ)
  local qw='query($login:String!,$from:DateTime!){user(login:$login){contributionsCollection(from:$from){contributionCalendar{totalContributions weeks{contributionDays{date contributionCount}}}}}}'
  if _cal_try "$(jq -n --arg q "$qw" --arg l "$login" --arg f "$from" '{query:$q, variables:{login:$l, from:$f}}')"; then
    mv "$tmp" "$body"; unset -f _cal_try; return 0
  fi
  # nothing usable — leave no file, so stats.jq takes the events approximation
  rm -f "$tmp"; unset -f _cal_try
}

# ── achievements scrape (plan.md §4) — isolated, defensive, never fatal ─────
fetch_achievements() { # login ttl
  local login=$1 ttl=$2; local dir="$CACHE_ROOT/$login"; mkdir -p "$dir"
  local body="$dir/medals.json"
  if [[ -n ${FIXDIR:-} ]]; then
    [[ -r "$FIXDIR/medals.json" ]] && cp "$FIXDIR/medals.json" "$body"; return 0
  fi
  if [[ ${OPT_NOSCRAPE:-0} == 1 ]]; then
    [[ -f $body ]] || echo '{"ok":false,"medals":[]}' > "$body"
    return 0
  fi
  if [[ -f $body ]]; then
    local age=$(( $(date +%s) - $(mtime "$body") ))
    (( age < ttl )) && return 0
  fi
  local html="$dir/.ach.html"
  if ! curl -sSL --max-time 15 -o "$html" "https://github.com/$login?tab=achievements" 2>/dev/null; then
    [[ -f $body ]] || echo '{"ok":false,"medals":[]}' > "$body"
    return 0
  fi
  # Parse defensively: names from alt="Achievement: X"; tier labels "x2" that
  # follow a name apply to it. Any parse hiccup → medals unavailable, never crash.
  local parsed
  parsed=$(awk '
    {
      line=$0
      while (match(line, /alt="Achievement: [^"]+"/)) {
        s=substr(line, RSTART+18, RLENGTH-19)
        if (!(s in seen)) { seen[s]=1; order[++n]=s; tier[s]=1 }
        last=s
        line=substr(line, RSTART+RLENGTH)
      }
      if (last != "" && match($0, /achievement-tier-label[^>]*>[^x<]*x[0-9]+/)) {
        t=substr($0, RSTART, RLENGTH); gsub(/.*x/, "", t); tier[last]=t+0
      }
    }
    END {
      printf "["
      for (i=1; i<=n; i++) {
        gsub(/"/, "", order[i])
        printf "%s{\"name\":\"%s\",\"tier\":%d}", (i>1?",":""), order[i], tier[order[i]]
      }
      printf "]"
    }' "$html" 2>/dev/null) || parsed=""
  if [[ -n $parsed ]] && jq -e . >/dev/null 2>&1 <<<"$parsed"; then
    jq -n --argjson m "$parsed" '{ok:true, medals:$m}' > "$body"
  else
    [[ -f $body ]] || echo '{"ok":false,"medals":[]}' > "$body"
  fi
  rm -f "$html"
}

# ── tier fetches ─────────────────────────────────────────────────────────────
# fast: notifications + own events (plan.md §5.1)
fetch_fast() { # login self
  local login=$1 self=$2; local dir="$CACHE_ROOT/$login"
  local ttl=$TTL_FAST; [[ $self == 1 ]] || ttl=$TTL_FRIEND
  if [[ $self == 1 && -z ${FIXDIR:-} ]]; then
    # the events API serves ≤300 events / 90 days (plan.md §12); one page is
    # a day or two for a busy account — fetch all three so the activity graph
    # shows weeks, not just today. Friends stay at one page (budget, §6).
    local p
    for p in 1 2 3; do
      gapi "$login" "events_p$p" "$ttl" "$API/users/$login/events?per_page=100&page=$p" || true
    done
    local -a epf=()
    for p in 1 2 3; do [[ -s $dir/events_p$p.json ]] && epf+=("$dir/events_p$p.json"); done
    if (( ${#epf[@]} )); then
      jq -s '[.[] | .[]?] | unique_by(.id)' "${epf[@]}" > "$dir/.events.merged" 2>/dev/null \
        && mv "$dir/.events.merged" "$dir/events.json"
    fi
  else
    gapi "$login" events "$ttl" "$API/users/$login/events?per_page=100" || true
  fi
  if [[ $self == 1 && -n $TOKEN ]]; then
    local pi=60
    [[ -f $dir/poll_interval ]] && pi=$(cat "$dir/poll_interval")
    (( pi < TTL_FAST )) && pi=$TTL_FAST
    gapi "$login" notifications "$pi" "$API/notifications?per_page=50" || true
  fi
}

# medium: stats recompute — searches, hygiene, calendar, alerts
fetch_medium() { # login self
  local login=$1 self=$2; local dir="$CACHE_ROOT/$login"
  local ttl=$TTL_MEDIUM; [[ $self == 1 ]] || ttl=$TTL_FRIEND
  local d7 d14; d7=$(date_ago 7) d14=$(date_ago 14)
  gapi "$login" merged     "$ttl" "$API/search/issues?q=$(search_q "is:pr author:$login is:merged merged:>$d7")&per_page=100" || true
  gapi "$login" approved   "$ttl" "$API/search/issues?q=$(search_q "is:pr author:$login review:approved updated:>$d7")&per_page=1" || true
  gapi "$login" changesreq "$ttl" "$API/search/issues?q=$(search_q "is:pr author:$login review:changes_requested updated:>$d7")&per_page=1" || true
  gapi "$login" reviewedby "$ttl" "$API/search/issues?q=$(search_q "is:pr reviewed-by:$login")&per_page=1" || true
  gapi "$login" starred    "$ttl" "$API/users/$login/starred?per_page=100&sort=created" "application/vnd.github.star+json" || true
  gql_calendar "$login" "$ttl"

  # repo hygiene: open issues/PRs idle >30d on top-5 recently-pushed repos
  # (plan.md §3 #5). The repo list refreshes on this tier too, so archiving a
  # repo drops it from hygiene/health within a minute — archived repos have
  # Dependabot disabled and shouldn't count against the pet.
  gapi "$login" repos "$ttl" "$API/users/$login/repos?per_page=100&sort=pushed" || true
  if [[ -f $dir/repos.json ]]; then
    local -a top5=()
    mapfile -t top5 < <(jq -r '[.[] | select((.fork | not) and (.archived | not))]
      | sort_by(.pushed_at) | reverse | .[0:5] | .[].full_name' "$dir/repos.json" 2>/dev/null)
    # cache files keyed by repo (not slot index) so a repo leaving the top-5
    # takes its cached alerts/issues with it instead of haunting the sums
    local -a issuefiles=() alertfiles=()
    local r slug
    for r in "${top5[@]}"; do
      slug=${r//\//__}
      gapi "$login" "issues_$slug" "$ttl" "$API/repos/$r/issues?state=open&sort=updated&direction=asc&per_page=50" || true
      [[ -s $dir/issues_$slug.json ]] && issuefiles+=("$dir/issues_$slug.json")
      if [[ $self == 1 && -n $TOKEN ]]; then
        # health (self only, needs auth): open Dependabot alerts (plan.md §3 #9)
        GAPI_SOFT=1
        gapi "$login" "alerts_$slug" "$ttl" "$API/repos/$r/dependabot/alerts?state=open&per_page=100" || true
        GAPI_SOFT=0
        [[ -s $dir/alerts_$slug.json ]] && alertfiles+=("$dir/alerts_$slug.json")
      fi
    done
    if (( ${#issuefiles[@]} )); then
      jq -s '[.[] | .[]?]' "${issuefiles[@]}" > "$dir/stale.json" 2>/dev/null || echo '[]' > "$dir/stale.json"
    else
      echo '[]' > "$dir/stale.json"
    fi
    if [[ $self == 1 && -n $TOKEN ]]; then
      if (( ${#alertfiles[@]} )); then
        jq -s '[.[] | .[]?] | map(.security_vulnerability.severity // .security_advisory.severity // "moderate")
               | {critical: (map(select(.=="critical"))|length),
                  high:     (map(select(.=="high"))|length),
                  moderate: (map(select(.=="moderate" or .=="medium" or .=="low"))|length)}' \
          "${alertfiles[@]}" > "$dir/alerts.json" 2>/dev/null || true
      else
        # every current top-5 repo has alerts disabled/none — a healthy pet
        echo '{"critical":0,"high":0,"moderate":0}' > "$dir/alerts.json"
      fi
    fi
  fi
  if [[ -n ${FIXDIR:-} ]]; then
    [[ -r "$FIXDIR/stale.json" ]] && cp "$FIXDIR/stale.json" "$dir/stale.json"
    [[ -r "$FIXDIR/alerts.json" ]] && cp "$FIXDIR/alerts.json" "$dir/alerts.json"
  fi
}

# slow: identity, achievements — 24h / on demand. The friend list rides the
# 5-minute friend tier instead: a follow should show up while you're looking,
# and ETag/304s make the extra polling free (plan.md §5.1 note).
fetch_slow() { # login self
  local login=$1 self=$2
  local ttl=$TTL_SLOW; [[ $self == 1 ]] || ttl=$TTL_SLOW
  if [[ $self == 1 && -n $TOKEN ]]; then
    gapi "$login" user "$ttl" "$API/user" || true
    # /user may 200 for a different login than requested; keep it only for self
  else
    gapi "$login" user "$ttl" "$API/users/$login" || true
  fi
  gapi "$login" repos "$ttl" "$API/users/$login/repos?per_page=100&sort=pushed" || true
  gapi "$login" orgs "$ttl" "$API/users/$login/orgs?per_page=1" || true
  fetch_achievements "$login" "$ttl"
  if [[ $self == 1 ]]; then
    gapi "$login" following "$TTL_FRIEND" "$API/users/$login/following?per_page=100" || true
  fi
}

cache_expire() { # login name — mark a cached file stale; the next fetch
  local f="$CACHE_ROOT/$1/$2.json"     # re-asks (ETag → 304 when unchanged)
  [[ -f $f ]] || return 0
  touch -m -t 200001010000 "$f" 2>/dev/null \
    || touch -m -d '2000-01-01' "$f" 2>/dev/null \
    || rm -f "$f"
}

fetch_all() { # login self — full pass (boot, friends)
  fetch_slow "$1" "$2"
  fetch_medium "$1" "$2"
  fetch_fast "$1" "$2"
}

# net status for the footer sync cell (design.md §5.9)
net_status() { [[ -f $NETDIR/status ]] && cat "$NETDIR/status" || echo ok; }
net_last_ok() { [[ -f $NETDIR/last_ok ]] && cat "$NETDIR/last_ok" || date +%s; }
net_retry_in() {
  local ra now; now=$(date +%s)
  [[ -f $NETDIR/retry_at ]] && ra=$(cat "$NETDIR/retry_at") || { echo 0; return; }
  (( ra > now )) && echo $((ra - now)) || echo 0
}
api_remaining() { [[ -f $NETDIR/api_remaining ]] && cat "$NETDIR/api_remaining" || echo "-"; }
