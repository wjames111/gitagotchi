# gitagotchi — lib/stats.jq
# The derive layer: pet_state = f(github_data, wall_clock)  (plan.md §1).
# Pure function of recorded API responses + $now — testable offline against
# fixtures. Emits shell-safe KEY='value' lines (@sh-quoted).
#
# Inputs (each --slurpfile, or --argjson null when absent):
#   $user $repos $events $merged $approved $changesreq $reviewedby $starred
#   $stale $alerts $calendar $notifications $medals $orgs $following
# Args: $now (epoch), $login

($now | tonumber) as $NOW
| (($user // [])          | .[0] // {})    as $U
| (($repos // [])         | .[0] // [])    as $RP
| (($events // [])        | .[0] // [])    as $EV
| (($merged // [])        | .[0] // {})    as $MG
| (($approved // [])      | .[0] // {})    as $AP
| (($changesreq // [])    | .[0] // {})    as $CR
| (($reviewedby // [])    | .[0] // {})    as $RB
| (($starred // [])       | .[0] // [])    as $ST
| (($stale // [])         | .[0] // [])    as $SI
| (($alerts // [])        | .[0])          as $AL
| (($calendar // [])      | .[0])          as $CAL
| (($notifications // []) | .[0])          as $NT
| (($medals // [])        | .[0] // {ok:false, medals:[]}) as $MD
| (($orgs // [])          | .[0] // [])    as $OG
| (($following // [])     | .[0] // [])    as $FW

# ── helpers ──────────────────────────────────────────────────────────────────
| def clamp(lo; hi): if . < lo then lo elif . > hi then hi else . end;
  def ep(ts): ((ts // "1970-01-01T00:00:00Z") | fromdateiso8601);
  def dago(ts): (($NOW - ep(ts)) / 86400);

# history honesty: sparklines re-run this program at PAST $now values against the
# SAME cached data. Every window below is lower-bound-only (`dago < N`), so events,
# stars, and merges that happened AFTER a past clock would leak backwards into it
# (hunger's decay term even goes exponential for future-dated merges). Mask future
# items at the source — a no-op at the live clock, correct at every past one.
  ([ $EV[] | select((.created_at | fromdateiso8601) <= $NOW) ]) as $EV
| ([ $ST[] | select((.starred_at // null) == null or ((.starred_at | fromdateiso8601) <= $NOW)) ]) as $ST

# ── account & identity facts ─────────────────────────────────────────────────
| ($U.created_at // "2020-01-01T00:00:00Z") as $created
| (dago($created)) as $acct_days
| ($U.id // 0) as $uid

# languages weighted by repo pushes (plan.md §7): recent pushes weigh double
| ([ $RP[] | select(.language != null)
    | {lang: .language, w: (if (.pushed_at != null and dago(.pushed_at) < 90) then 2 else 1 end)} ]
   | group_by(.lang) | map({lang: .[0].lang, w: (map(.w) | add)})
   | sort_by(-.w, .lang)) as $langs
| ($langs | length) as $nlangs
| (if $nlangs > 0 then $langs[0].lang else "" end) as $top_lang
| (if $nlangs > 1 then $langs[1].lang else "" end) as $second_lang

# ── event stream (energy, sleep, hibernation, fitness fallback) ──────────────
| ([ $EV[] | .created_at | fromdateiso8601 ] | sort | reverse) as $evt
| ($evt | length) as $nev
| (if $nev > 0 then $evt[0] else null end) as $last_evt
| (if $last_evt != null then (($NOW - $last_evt) / 86400)
   else ($acct_days) end) as $dq_events

# rest gaps ≥ 6h whose end touches the last 24h (timeline: now, then events)
| ([$NOW] + $evt) as $tl
| ([ range(0; (($tl | length) - 1)) as $i
     | { gap: ($tl[$i] - $tl[$i+1]), endt: $tl[$i] }
     | select(.gap >= 21600 and .endt >= ($NOW - 86400)) ] | length) as $rest_gaps
| (if $rest_gaps > 0 then 1 else 0 end) as $has_gap

# personal baseline (plan.md §3.2): your own trailing rate, not absolute numbers
| ([ $evt[] | select(. >= $NOW - 14*86400) ] | length) as $n14
| ($n14 / 14) as $rate14
| (if $nev > 1 then (($NOW - $evt[$nev-1]) / 86400) | clamp(1; 90) else 14 end) as $span
| (($nev / $span)) as $baseline
| ($rate14 / (if $baseline < 0.1 then 0.1 else $baseline end)) as $ratio

# 2 — energy: rested by quiet gaps, drained by sustained >1.75× pace (plan.md §3)
| ((if $has_gap == 1 then 58 else 30 end)
   + (8 * ([$rest_gaps - 1, 0] | max | [., 2] | min))
   + (if $rate14 < ($baseline * 0.6) then 12 else 0 end)
   - ((($ratio - 1.75) * 35) | clamp(0; 70))
  | clamp(0; 100) | round) as $energy

# 1 — hunger: merged PRs 7d, each 14·0.5^(days_ago/2) (plan.md §3) — the
# 2-day half-life is deliberate weekend forgiveness: energy celebrates rest
# gaps, so hunger shouldn't punish the same two quiet days
| ($MG.items // []) as $mgi
| ([ $mgi[] | (.pull_request.merged_at // .closed_at) | select(. != null) | dago(.) | select(. >= 0) ]) as $mdays
| (([ $mdays[] | 14 * pow(0.5; . / 2) ] | add // 0) | clamp(0; 100) | round) as $hunger
| ($mdays | length) as $merges7
| (if ($mgi | length) > 0
   then ($mgi | sort_by(.pull_request.merged_at // .closed_at) | last) else null end) as $newest
| (if $newest != null then ($newest.number | tostring) else "" end) as $merge_num
| (if $newest != null then ($newest.html_url // "") else "" end) as $merge_url
| (if $newest != null
   then ((dago($newest.pull_request.merged_at // $newest.closed_at)) * 24 | floor) else -1 end) as $merge_ago_h

# quiet time = min(events gap, newest-merge gap) — merges prove liveness even
# when the events feed is unavailable; then sleep/hibernation (plan.md §3.3)
| ([ $dq_events, (if ($mdays | length) > 0 then ($mdays | min) else 99999 end) ] | min) as $days_quiet
| ($days_quiet * 24) as $hours_quiet
| (($NOW | strflocaltime("%H") | tonumber)) as $lhour
| (if ($hours_quiet >= 6) or ($lhour < 6 and $hours_quiet >= 2) then 1 else 0 end) as $sleeping
| (if $days_quiet >= 30 then 1 else 0 end) as $hib
| (if $days_quiet >= 21 and $hib == 0 then 1 else 0 end) as $drowsy

# 3 — mood: net social feedback last 7d, squashed into 5 buckets (plan.md §3)
| (($AP.total_count // 0) + $merges7 - 2 * ($CR.total_count // 0)) as $mood_raw
| (if $mood_raw <= -3 then {v: 12, b: "miserable"}
   elif $mood_raw < 0  then {v: 32, b: "grumpy"}
   elif $mood_raw <= 8 then {v: 52, b: "neutral"}
   elif $mood_raw <= 24 then {v: 72, b: "content"}
   else {v: 92, b: "ecstatic"} end) as $mood

# 4 — fitness: active days of last 21 (calendar when authed, events otherwise)
| (if $CAL != null
   then ([ $CAL.data.user.contributionsCollection.contributionCalendar.weeks[]?
           .contributionDays[]?
           | select(.contributionCount > 0 and (dago(.date + "T12:00:00Z") < 21)) ] | length)
   else ([ $evt[] | select(. >= $NOW - 21*86400) | strftime("%Y-%m-%d") ] | unique | length)
   end | [., 21] | min) as $active21
| ((100 * pow($active21 / 21; 1.3)) | round) as $fitness
| (if $CAL != null
   then ($CAL.data.user.contributionsCollection.contributionCalendar.totalContributions // 0)
   else ([$nev * 3, 999] | min) end) as $contrib

# 5 — cleanliness: repo hygiene on top-N recently-pushed repos (plan.md §3)
| ([ $SI[] | select(.updated_at != null and dago(.updated_at) > 30) ]) as $stalei
| ([ $stalei[] | select(.pull_request == null) ] | length) as $stale_issues
| ([ $stalei[] | select(.pull_request != null) ] | length) as $stale_prs
| ((100 - 12 * $stale_issues - 6 * $stale_prs) | clamp(0; 100)) as $clean
| (if ($stalei | length) > 0
   then ($stalei | group_by(.repository_url) | sort_by(-length) | .[0][0].repository_url
         | split("/") | .[-1])
   else "" end) as $dirty_repo

# 6 — curiosity: stars given + forks made 14d, new language 30d, plus the
# everyday signal — how many DIFFERENT repos you touched this month (6 pts
# each up to 8). Exploration is mostly wandering between projects, not the
# rare star/fork; without this term almost every account sat below 20.
| ([ $ST[] | select((.starred_at // null) != null and dago(.starred_at) < 14) ] | length) as $stars14
| ([ $EV[] | select(.type == "ForkEvent" and dago(.created_at) < 14) ] | length) as $forks14
| ([ $RP[] | select(.language != null and .created_at != null and dago(.created_at) >= 30) | .language ]
   | unique) as $old_langs
| ([ $RP[] | select(.language != null and .created_at != null and dago(.created_at) < 30)
     | .language ] | unique | map(select(. as $l | $old_langs | index($l) | not)) | .[0] // "") as $new_lang
| ([ $EV[] | select(dago(.created_at) < 30) | (.repo.name // "") | select(. != "") ]
   | unique | length) as $repos30
| ((6 * $stars14 + 10 * $forks14 + (if $new_lang != "" then 15 else 0 end)
    + 5 * ([$repos30, 8] | min))
   | clamp(0; 100)) as $curiosity

# 7 — social: outbound comments/reviews on others' repos 7d on a square-root
# curve (7·√n — the 4th comment is worth less than the 1st, and saturating
# takes ~200), plus the friends you keep — 1 pt per followed account up to 20
# (the graph opens the door; conversation carries the score) (plan.md §3)
| ([ $EV[]
    | select(.type == "IssueCommentEvent" or .type == "PullRequestReviewEvent"
             or .type == "PullRequestReviewCommentEvent" or .type == "CommitCommentEvent")
    | select(dago(.created_at) < 7)
    | select((.repo.name // "") | startswith($login + "/") | not) ] | length) as $outbound7
| ((7 * ($outbound7 | sqrt) + ([($FW | length), 20] | min)) | clamp(0; 100) | round) as $social
# visitors: whoever you've interacted with in the LAST HOUR — their pets
# drop by on the stage (owners of repos you commented/reviewed on)
| ([ $EV[]
    | select(.type == "IssueCommentEvent" or .type == "PullRequestReviewEvent"
             or .type == "PullRequestReviewCommentEvent" or .type == "CommitCommentEvent")
    | select(dago(.created_at) < (1 / 24))
    | select((.repo.name // "") | startswith($login + "/") | not)
    | ((.repo.name // "") | split("/")[0]) | select(. != "") ]
   | unique | .[0:3]) as $visitors
# bond ledger: who you actually talk to — for every comment/review event,
# the counterpart is the author of the issue/PR (person-level, so org-repo
# collaboration counts), falling back to the repo owner; self excluded.
# Tallied over the whole events window; the compare view sums both sides'
# ledgers into a relationship status.
| ([ $EV[]
    | select(.type == "IssueCommentEvent" or .type == "PullRequestReviewEvent"
             or .type == "PullRequestReviewCommentEvent" or .type == "CommitCommentEvent")
    | (.payload.issue.user.login // .payload.pull_request.user.login
       // ((.repo.name // "") | split("/")[0]))
    | select(. != "" and . != $login) ]
   | group_by(.) | sort_by(-length) | .[0:30]
   | map("\(.[0])|\(length)") | join(";")) as $comms

# 8 — wisdom: reviews given + language diversity + account age; slow log-scale
| ($RB.total_count // 0) as $reviews_total
| ((7 * ((1 + $reviews_total) | log) + 3 * ([$nlangs, 8] | min) + 1.5 * ($acct_days / 365))
   | clamp(0; 100) | round) as $wisdom

# 9 — health (self only, needs auth): Dependabot alerts (plan.md §3)
| (if $AL != null
   then ((100 - 20 * ($AL.critical // 0) - 10 * ($AL.high // 0) - 5 * ($AL.moderate // 0))
         | clamp(0; 100))
   else null end) as $health

# 10 — happiness (plan.md §3.1); health weight redistributes when unknown
# Weights favour the stats that actually MOVE on a day scale. fitness, clean and
# health sit pinned at 100 for any healthy active account and wisdom grows on a
# scale of years, so a fat weight on them is dead weight twice over: it anchors
# the composite high AND it steals authority from the vitals the pet visibly
# acts out. At 10/10/5/5 that inert block was 30% of happiness, which left
# hunger's 20% weaker than the 30% of energy+social+curiosity that could offset
# it — a pet could slide 82→54 hungry over 30h while the number moved 1 point
# (the misery cap doesn't bite until <20, so nothing caught it). Halved to 15%
# and the 15 points moved to hunger/energy/mood. Keep these as whole percents
# summing to 100: panels.sh VX_COMP_W renders them as integer bars.
| ({hunger: $hunger, energy: $energy, mood: $mood.v, fitness: $fitness, clean: $clean,
    curiosity: $curiosity, social: $social, wisdom: $wisdom}) as $S9
| ((0.28*$hunger + 0.18*$energy + 0.24*$mood.v + 0.05*$fitness + 0.05*$clean
    + 0.05*$curiosity + 0.10*$social + 0.02*$wisdom
    + (if $health != null then 0.03*$health else 0 end))
   / (if $health != null then 1.0 else 0.97 end) | round) as $happy_raw
| ($S9 + (if $health != null then {health: $health} else {} end)) as $SM
# the misery cap listens to SURVIVAL needs only: hunger, energy, mood, clean,
# health. The slow, aspirational stats (curiosity, wisdom, fitness, social)
# still weigh on the composite but can't hard-cap it — a pet that didn't
# star a repo this fortnight isn't starving, and capping on them flattened
# every active friend to exactly 60.
| ([ $SM | to_entries[]
     | select(.key == "hunger" or .key == "energy" or .key == "mood"
              or .key == "clean" or .key == "health")
     | select(.value < 20) ] | sort_by(.value)) as $starving
| (if ($starving | length) > 0 then ([$happy_raw, 60] | min) else $happy_raw end) as $happiness
# report the cap only when it actually binds (raw composite would exceed 60)
| (($starving | length) > 0 and $happy_raw > 60) as $capbind
| (if $capbind then $starving[0].key else "" end) as $capped_by
| (if $capbind then ($starving[0].value | tostring) else "" end) as $capped_val
# the face reads the WHOLE pet, not just its temper: the mouth tracks overall
# happiness so a card's smile agrees with the happiness number above it. Bands
# are built so the middle (~40–64) is a straight face — 48 is neither happy nor
# sad. Mood still colours the temper copy (§6.5), but no longer drives the mouth.
| (if   $happiness >= 80 then "ecstatic"
   elif $happiness >= 65 then "content"
   elif $happiness >= 40 then "neutral"
   elif $happiness >= 25 then "grumpy"
   else "miserable" end) as $face_bucket

# ── life stage (plan.md §2.3) ────────────────────────────────────────────────
| (if $acct_days < 7 then "egg"
   elif $acct_days < 90 or $contrib < 50 then "hatchling"
   elif $acct_days < 730 or $contrib < 500 then "kid"
   elif $acct_days < 3650 then "adult"
   else "elder" end) as $stage

# ── notifications → mail / review scroll / security pre-warn (plan.md §5) ────
| ($NT // []) as $nts
# the envelope counts like GitHub's bell: every unread notification except
# review requests (the ⎘ scroll) and security alerts (the sick pre-warn)
| ([ $nts[] | select(.reason != "review_requested" and .reason != "security_alert") ] | length) as $mail
| ([ $nts[] | select(.reason == "review_requested") ]) as $rr
| ($rr | length) as $rrn
| (if $rrn > 0
   then ($rr[0].subject.url // "" | sub("api\\.github\\.com/repos"; "github.com") | sub("/pulls/"; "/pull/"))
   else "" end) as $rr_url
| ([ $nts[] | select(.reason == "security_alert") ] | length) as $secn

# ── dense mode (ux-spec §9): 60d activity histogram, annotations, feed ──────
# The events API caps at ~300 events, a few days for a busy account; the
# contribution calendar covers the whole year — use it when authed, fall
# back to raw events when not.
| (if $CAL != null
   then ([ $CAL.data.user.contributionsCollection.contributionCalendar.weeks[]?
           .contributionDays[]? ] | map({key: .date, value: .contributionCount})
         | from_entries)
   else null end) as $calmap
| ([ $EV[] | .created_at | fromdateiso8601 | strftime("%Y-%m-%d") ]
   | group_by(.) | map({key: .[0], value: length}) | from_entries) as $daymap
| ([ range(0; 60) | ($NOW - (59 - .) * 86400) | strftime("%Y-%m-%d") ]) as $daykeys
| ([ $daykeys[] | (if $calmap != null then ($calmap[.] // 0) else ($daymap[.] // 0) end) ]) as $evdays
| (if $calmap != null then "contributions" else "events" end) as $act_src
| (($evdays | max) // 0) as $evpeak
| ($evdays[59] // 0) as $evtoday
# graph baseline: your own trailing 90d average from the same source
| (if $calmap != null
   then ((([ range(0; 90) | ($NOW - . * 86400) | strftime("%Y-%m-%d") ]
           | map($calmap[.] // 0) | add) * 100 / 90) | round)
   else ($baseline * 100 | round) end) as $act_base_x100
# rest-gap annotation: the longest zero-run in the 60d histogram
| ((reduce range(0; 60) as $i ({best: null, cur: null};
      if $evdays[$i] == 0 then
        .cur = (if .cur == null then {s: $i, l: 1} else {s: .cur.s, l: (.cur.l + 1)} end)
      else
        (if .cur != null and (.best == null or .cur.l > .best.l) then .best = .cur else . end)
        | .cur = null
      end))
   | (if .cur != null and (.best == null or .cur.l > .best.l) then .best = .cur else . end)
   | .best) as $zrun
| (if $zrun != null and $zrun.l >= 2 and $zrun.l < 60
   then {idx: (($zrun.s + $zrun.l / 2) | floor), days: $zrun.l} else null end) as $gapann
| (if $newest != null
   then (59 - ((dago($newest.pull_request.merged_at // $newest.closed_at)) | floor)) else -1 end) as $mergeidx
# every merge day in the window — the expanded graph ticks them all (▲)
| ([ $mgi[] | (.pull_request.merged_at // .closed_at) | select(. != null)
    | (59 - (dago(.) | floor)) | select(. >= 0 and . <= 59) ] | unique) as $mergeidxs

# expanded activity (panels mockup): weekday rhythm 90d, 12-week calendar,
# and 1y week-granularity columns (calendar-sourced; empty when unauthed)
| ([ range(0; 90) | ($NOW - . * 86400) ]
   | map({dw: (strftime("%u") | tonumber), k: strftime("%Y-%m-%d")})
   | group_by(.dw)
   | map((map(if $calmap != null then ($calmap[.k] // 0) else ($daymap[.k] // 0) end)
          | (add * 10 / length) | round))) as $wkavg
| ([ range(0; 84) | ($NOW - (83 - .) * 86400) | strftime("%Y-%m-%d") ]
   | map(if $calmap != null then ($calmap[.] // 0) else ($daymap[.] // 0) end)) as $cal84
| (if $calmap != null
   then ([ range(0; 364) | ($NOW - (363 - .) * 86400) | strftime("%Y-%m-%d") ]
         | map($calmap[.] // 0)) as $ydays
        | [ range(0; 52) | . as $w | ($ydays[$w*7 : $w*7+7] | add) ]
   else [] end) as $evweeks

# feed panel: the liveness log — it teaches the stat system by narrating it.
# Every entry carries its GitHub html url so the terminal can hyperlink it.
| def hurl(u): (u // "")
    | sub("api\\.github\\.com/repos"; "github.com") | sub("/pulls/"; "/pull/");
  ( [ $mgi[0:8][] | (dago(.pull_request.merged_at // .closed_at)) as $md
      | {t: ep(.pull_request.merged_at // .closed_at), tag: "merge",
         tx: ("PR #\(.number) merged in \((.repository_url // "?") | split("/") | last)"),
         fx: ("+\(14 * pow(0.5; $md / 2) | round) hunger"),
         u: (.html_url // ""), ttl: (.title // "")} ]
  + [ $nts[] | select(.reason == "review_requested")
      | {t: ep(.updated_at), tag: "review",
         tx: ("review requested · \(.subject.title // "?")"), fx: "",
         u: hurl(.subject.url)} ]
  + [ $nts[] | select(.reason == "mention" or .reason == "team_mention"
                      or .reason == "comment" or .reason == "author")
      | {t: ep(.updated_at), tag: "mention",
         tx: ("\(.reason | gsub("_"; " ")) · \(.subject.title // "?")"), fx: "",
         u: hurl(.subject.url)} ]
  + [ $nts[] | select(.reason == "security_alert")
      | {t: ep(.updated_at), tag: "sec",
         tx: ("security alert · \(.subject.title // "?")"), fx: "",
         u: hurl(.subject.url)} ]) as $fbase
| ([ range(0; (($tl | length) - 1)) as $i
     | {gap: ($tl[$i] - $tl[$i+1]), endt: $tl[$i]}
     | select(.gap >= 21600 and .endt >= $NOW - 7*86400 and .endt < $NOW)
     | {t: .endt, tag: "rest", tx: "\(.gap / 3600 | floor)h quiet gap detected",
        fx: ("+\([(.gap / 3600 | floor), 12] | min) energy"), u: ""} ]
   | .[0:6]) as $rests
| (($fbase + ([ $rests[] | select(.t >= $NOW - 2*86400) ] | .[0:2]))
   | sort_by(-.t) | .[0:8]
  | map("\(if ($NOW - .t) < 86400 then (.t | strflocaltime("%H:%M"))
           else (.t | strflocaltime("%b %d")) end)|\(.tag)|\(.tx | gsub("[|;\n\r]"; " ") | .[0:64])|\(.fx)|\(.u | gsub("[|;\n\r]"; ""))")
  | join(";;")) as $feedraw
# expanded feed (panels mockup): more entries, day-keyed for grouping —
# daykey|daylabel|hh:mm|tag|text|effect|url|linklabel (PR title on merges)
| (($fbase + $rests) | sort_by(-.t) | .[0:30]
   | map("\(.t | strflocaltime("%Y-%m-%d"))|\(.t | strflocaltime("%b %d") | ascii_downcase)|\(.t | strflocaltime("%H:%M"))|\(.tag)|\(.tx | gsub("[|;\n\r]"; " ") | .[0:72])|\(.fx)|\(.u | gsub("[|;\n\r]"; ""))|\(.ttl // "" | gsub("[|;\n\r]"; " ") | .[0:26])")
   | join(";;")) as $feedxraw

# ── output: shell-safe K='v' lines ───────────────────────────────────────────
| [
  "ID=\($uid | tostring | @sh)",
  "LOGIN=\(($U.login // $login) | @sh)",
  "CREATED=\($created | @sh)",
  "CREATED_YEAR=\($created[0:4] | @sh)",
  "ACCT_DAYS=\($acct_days | floor | tostring | @sh)",
  "FOLLOWERS=\(($U.followers // 0) | tostring | @sh)",
  "FOLLOWING_N=\(($FW | length) | tostring | @sh)",
  "BIO_SET=\(if ($U.bio // "") != "" then "true" else "false" end | @sh)",
  "HIREABLE=\(if $U.hireable == true then "true" else "false" end | @sh)",
  "ADMIN_OR_PRO=\(if ($U.site_admin == true or ($U.plan.name // "" | ascii_downcase) == "pro") then "true" else "false" end | @sh)",
  "ORG_MEMBER=\(if ($OG | length) > 0 then "true" else "false" end | @sh)",
  "TOP_LANG=\($top_lang | @sh)",
  "SECOND_LANG=\($second_lang | @sh)",
  "NLANGS=\($nlangs | tostring | @sh)",
  "STAGE=\($stage | @sh)",

  "HUNGER=\($hunger | tostring | @sh)",
  "ENERGY=\($energy | tostring | @sh)",
  "MOOD=\($mood.v | tostring | @sh)",
  "MOOD_BUCKET=\($mood.b | @sh)",
  "FACE_BUCKET=\($face_bucket | @sh)",
  "FITNESS=\($fitness | tostring | @sh)",
  "CLEAN=\($clean | tostring | @sh)",
  "CURIOSITY=\($curiosity | tostring | @sh)",
  "SOCIAL=\($social | tostring | @sh)",
  "WISDOM=\($wisdom | tostring | @sh)",
  "HEALTH=\(if $health != null then ($health | tostring) else "" end | @sh)",
  "HAPPINESS=\($happiness | tostring | @sh)",
  "HAPPY_RAW=\($happy_raw | tostring | @sh)",
  "CAPPED_BY=\($capped_by | @sh)",
  "CAPPED_VAL=\($capped_val | @sh)",

  "MERGES7=\($merges7 | tostring | @sh)",
  "MERGE_NUM=\($merge_num | @sh)",
  "MERGE_URL=\($merge_url | @sh)",
  "MERGE_AGO_H=\($merge_ago_h | tostring | @sh)",
  "APPROVED7=\(($AP.total_count // 0) | tostring | @sh)",
  "CHANGESREQ7=\(($CR.total_count // 0) | tostring | @sh)",
  "ACTIVE21=\($active21 | tostring | @sh)",
  "STALE_ISSUES=\($stale_issues | tostring | @sh)",
  "STALE_PRS=\($stale_prs | tostring | @sh)",
  "DIRTY_REPO=\($dirty_repo | @sh)",
  "STARS14=\($stars14 | tostring | @sh)",
  "FORKS14=\($forks14 | tostring | @sh)",
  "REPOS30=\($repos30 | tostring | @sh)",
  "NEW_LANG=\($new_lang | @sh)",
  "OUTBOUND7=\($outbound7 | tostring | @sh)",
  "VISITORS=\($visitors | join(" ") | @sh)",
  "COMMS_RAW=\($comms | @sh)",
  "REVIEWS_TOTAL=\($reviews_total | tostring | @sh)",

  "DAYS_QUIET=\($days_quiet | floor | tostring | @sh)",
  "HOURS_QUIET=\($hours_quiet | floor | tostring | @sh)",
  "REST_GAPS=\($rest_gaps | tostring | @sh)",
  "RATIO_X100=\(($ratio * 100 | round) | tostring | @sh)",
  "SLEEPING=\($sleeping | tostring | @sh)",
  "HIB=\($hib | tostring | @sh)",
  "DROWSY=\($drowsy | tostring | @sh)",
  "WARMTH=\((7 * $nev) | clamp(0; 100) | tostring | @sh)",

  "MAIL=\($mail | tostring | @sh)",
  "REVIEW_REQ=\($rrn | tostring | @sh)",
  "REVIEW_URL=\($rr_url | @sh)",
  "SEC_WARN=\(if $secn > 0 then "1" else "0" end | @sh)",

  "MEDALS_OK=\(if $MD.ok == true then "1" else "0" end | @sh)",
  "MEDALS_RAW=\([ ($MD.medals // [])[] | "\(.name)|\(.tier // 1)" ] | join(";") | @sh)",

  "EVDAYS=\($evdays | map(tostring) | join(" ") | @sh)",
  "EV_PEAK=\($evpeak | tostring | @sh)",
  "EV_TODAY=\($evtoday | tostring | @sh)",
  "ACT_SRC=\($act_src | @sh)",
  "BASE_PD_X100=\($act_base_x100 | tostring | @sh)",
  "GAP_IDX=\(if $gapann != null then ($gapann.idx | tostring) else "" end | @sh)",
  "GAP_DAYS=\(if $gapann != null then ($gapann.days | tostring) else "" end | @sh)",
  "MERGE_IDX=\($mergeidx | tostring | @sh)",
  "MERGE_IDXS=\($mergeidxs | map(tostring) | join(" ") | @sh)",
  "FEED_RAW=\($feedraw | @sh)",
  "FEEDX_RAW=\($feedxraw | @sh)",
  "WKDAY_X10=\($wkavg | map(tostring) | join(" ") | @sh)",
  "CAL84=\($cal84 | map(tostring) | join(" ") | @sh)",
  "EVWEEKS=\($evweeks | map(tostring) | join(" ") | @sh)"
] | .[]
