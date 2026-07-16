# gitagotchi — lib/screens.sh
# The §5 screen catalog: main, stat detail, friends, friend view, compare,
# help overlay, degraded/egg/too-small states, onboarding beats.

# ── main screen (§5.2) ──────────────────────────────────────────────────────
draw_main() { # assoc_name self
  local -n P=$1
  local self=$2
  IW=$((COLS - 2))
  local is_egg=0; [[ ${P[STAGE]:-} == egg ]] && is_egg=1
  # state legality (§8.4): floor props only when the pet is idle and hatched
  gate_props "$ANIM_STATE" "${P[STAGE]:-}"

  # bottom block: horizon+voice+dash rows; stage gets the rest (air → stage, §3)
  insight_text "$1"; [[ $self != 1 ]] && INSIGHT=""
  local -a ins=()
  if [[ -n $INSIGHT ]]; then
    local maxw=$((IW - 5)) t=$INSIGHT
    if (( ${#t} > maxw )); then
      local cut=${t:0:maxw}
      local first=${cut% *}
      ins=("$first" "$(trunc "${t:${#first}+1}" "$maxw")")
    else ins=("$t"); fi
  fi
  local unauth=0; [[ $self == 1 && $AUTH_MODE == none ]] && unauth=1
  local dhint=0
  if [[ $self == 1 && -n $PIX_MODE && ${DENSE_FORCE:-} != 0 ]] && (( ! unauth )) && ! dense_active; then
    dhint=1
  fi
  local bottom=$(( 1 + 1 + 1 + 3 + ${#ins[@]} + (unauth ? 2 : 0) + dhint + 1 ))
  local spare=$(( LINES - 1 - bottom - 8 ))   # 8 = comfortable stage
  local sp_v=0 sp_h=0 sp_b=0                  # spacers: after voice/around bars
  (( spare >= 1 )) && sp_v=1
  (( spare >= 2 )) && sp_h=1
  (( spare >= 3 )) && sp_b=1
  SH=$(( LINES - 1 - bottom - sp_v - sp_h - sp_b ))
  (( SH < 5 )) && SH=5

  SCREEN=()
  # title bar: identity left, live indicators pinned right (§3, §5.2)
  local left_p left_c
  if (( TICK < FLASH_UNTIL )) && [[ -n $FLASH_TEXT ]]; then
    left_p="$FLASH_TEXT"
    left_c="${C_GREEN}$(osc8 "$FLASH_URL" "$FLASH_TEXT")${RS}"
  elif [[ $self == 1 ]]; then
    left_p="${P[NAME]} · ${P[SPECIES_LABEL]} · ${P[STAGE]}"
    left_c="${C_BOLD}${P[NAME]}${RS}${C_CHROME} · ${RS}${P[SPECIES_LABEL]}${C_CHROME} · ${RS}${P[STAGE]}"
  else
    left_p="@${P[LOGIN]}'s ${P[NAME]} · ${P[SPECIES_LABEL]} · ${P[STAGE]}"
    left_c="${C_CHROME}@${P[LOGIN]}'s ${RS}${C_BOLD}${P[NAME]}${RS}${C_CHROME} · ${RS}${P[SPECIES_LABEL]}${C_CHROME} · ${RS}${P[STAGE]}"
  fi
  local bp="" bc=""
  if [[ $self == 1 && $AUTH_MODE != none ]]; then     # no ✉/⎘ slots on friends (§5.6) or unauth (§5.9)
    local show=1
    (( TICK < BADGE_BLINK_UNTIL )) && (( (TICK / 2) % 2 )) && show=0
    if (( ${P[MAIL]:-0} > 0 )) && (( show )); then
      bp+=" [${G_MAIL} ${P[MAIL]}]"
      bc+=" ${C_MAILC}$(osc8 "https://github.com/notifications" "[${G_MAIL} ${P[MAIL]}]")${RS}"
    fi
    if (( ${P[REVIEW_REQ]:-0} > 0 )) && (( show )); then
      bp+=" [${G_SCROLL} ${P[REVIEW_REQ]}]"
      bc+=" ${C_SCROLLC}$(osc8 "${P[REVIEW_URL]}" "[${G_SCROLL} ${P[REVIEW_REQ]}]")${RS}"
    fi
  fi
  push_title "$left_p" "$bp" "$bc" 2>/dev/null || push_title "$left_p" "$bp" "$bc"

  # ── stage ──
  stage_reset
  local dimlab=""
  [[ $ANIM_STATE == sleep ]] && dimlab=$C_DIM

  if (( is_egg )); then
    # the egg IS the pet (§5.9): wiggle by tick, more with warmth
    local tilt=0 wob=$(( ${P[WARMTH]:-0} > 50 ? 6 : 12 ))
    (( (TICK / wob) % 4 == 1 )) && tilt=-1
    (( (TICK / wob) % 4 == 3 )) && tilt=1
    egg_frame "$tilt" "$(fg "${P[COLOR256]:-180}")"
    local ex=$(( (IW - 7) / 2 )) et=$(( SH - 3 )) i
    for i in "${!SPCOMP_PLAIN[@]}"; do
      stage_put $((et + i)) "$ex" "${#SPCOMP_PLAIN[i]}" "${SPCOMP_COL[i]}"
    done
  else
    # medal shelf on the stage's right edge (§3)
    shelf_lines "${P[MEDALS_RAW]:-}" "${P[MEDALS_OK]:-0}"
    if (( ${#SHELF[@]} > 0 )); then
      local i
      for i in "${!SHELF[@]}"; do
        stage_put "$i" $((IW - SHELF_W - 1)) "$SHELF_W" "${SHELF[i]}"
      done
    fi
    # window vignette: pet stares out a little window (§5.3)
    if [[ $VIG_CUR == window ]] && (( GATE_PROPS )); then
      stage_put 0 2 3 "${C_CHROME}┌─┐${RS}"
      stage_put 1 2 3 "${C_CHROME}│ │${RS}"
      stage_put 2 2 3 "${C_CHROME}└─┘${RS}"
    fi
    # cobwebs: 90+ days quiet — corner web + a spider on a swaying thread
    if cobwebbed "$1"; then
      local -a web=("${COBWEB_TL[@]}")
      [[ $TIER == A ]] && web=("${COBWEB_TL_A[@]}")
      local wi
      for wi in "${!web[@]}"; do
        stage_put "$wi" 1 "${#web[wi]}" "${C_CHROME}${C_DIM}${web[wi]}${RS}"
      done
      local spx=$(( IW * 3 / 4 + (TICK / 8) % 2 ))
      local spl=$(( 2 + (TICK / 16) % 2 ))
      local sr
      for ((sr=0; sr<spl && sr<SH-1; sr++)); do
        stage_put "$sr" "$spx" 1 "${C_CHROME}${C_DIM}╎${RS}"
      done
      stage_put "$spl" "$spx" 1 "${C_CHROME}●${RS}"
    fi

    # the pet — pixel species carry their own cocoon/thermometer/bowl frames;
    # the ASCII tier uses the global cocoon + glyph overlays (§6.1)
    local haspix=0
    [[ -n $PIX_MODE && -n ${PIXF[${P[SPECIES]}/idle_1]:-} ]] && haspix=1
    local faint=0
    [[ $ANIM_STATE == sick ]] && faint=1   # sick renders pale (§2.2, gallery)
    if [[ ( $ANIM_STATE == hib || ${WAKE_PHASE:-0} == 1 ) && $haspix == 0 ]]; then
      # ASCII tier: the global cocoon; during wake phase 1 it shakes fast
      local cph=$(( (TICK / 4) % 2 ))
      [[ ${WAKE_PHASE:-0} == 1 ]] && cph=$(( TICK % 2 ))
      cocoon_frame "$cph" "$(fg "${P[COLOR256]:-180}")"
      PET_LINES=("${SPCOMP_COL[@]}"); PET_H=${#PET_LINES[@]}
      PET_W=0; local l; for l in "${SPCOMP_PLAIN[@]}"; do (( ${#l} > PET_W )) && PET_W=${#l}; done
    else
      local frame=$ANIM_FRAME
      [[ $VIG_CUR == belly ]] && (( GATE_PROPS )) && frame=belly
      pet_compose "$1" "$frame" "$ANIM_BLINK" "$faint"
    fi
    local petx=$(( (IW - PET_W) / 2 + PET_XOFF ))
    (( petx < 1 )) && petx=1
    (( petx + PET_W > IW - 1 )) && petx=$(( IW - 1 - PET_W ))
    # the bliss float. Cozy has no z-layer — it is built row by row, and the pet
    # IS most of the screen here — so instead of crossing panels the way dense
    # does, the float lerps the pet from the ground to the middle of its stage.
    local pet_top=$(( SH - PET_H )) i
    if (( ${BLISS_T:-0} > 0 )); then
      local _mid=$(( (SH - PET_H) / 2 + (TICK / 8) % 2 ))
      pet_top=$(( pet_top + (_mid - pet_top) * BLISS_T / 100 ))
      (( pet_top < 0 )) && pet_top=0
    fi
    for i in "${!PET_LINES[@]}"; do
      local w=$PET_W
      [[ -z ${PIX_MODE} || -z ${PIXF[${P[SPECIES]}/idle_1]:-} ]] && w=${#SPCOMP_PLAIN[i]}
      stage_put $((pet_top + i)) "$petx" "$w" "${PET_LINES[i]}"
    done

    # sick: ASCII tier adds the thermometer glyph (pixel frames draw their own)
    if [[ $ANIM_STATE == sick && $haspix == 0 ]]; then
      stage_put $((pet_top + 1)) $((petx + PET_W + 1)) ${#G_THERMO} "${C_SECWARN}${G_THERMO}${RS}"
    fi
    # flies orbit a messy pet (§5.3)
    if [[ $VIG_CUR == flies ]] && (( GATE_PROPS )); then
      local fly=$G_FLY1; (( TICK % 4 < 2 )) && fly=$G_FLY2
      stage_put $((pet_top)) $((petx - 4)) 3 "${C_CHROME}${fly}${RS}"
      stage_put $((pet_top + 1)) $((petx + PET_W + 1)) 3 "${C_CHROME}${fly}${RS}"
    fi
    # ball: curiosity ≥ 60 → pet bats it between two columns (§5.3)
    if [[ $VIG_CUR == ball ]] && (( GATE_PROPS )); then
      local bx=$(( petx - 6 - ((TICK / 6) % 2) * 3 ))
      stage_put $((SH - 1)) "$bx" 1 "$(fg 111)${G_BALL}${RS}"
    fi
    # floaters: hearts, +N, zZz, 💤? — 1 row/tick, spawn at pet, expire at top
    local fl
    for fl in "${FLOATERS[@]}"; do
      local frow=${fl%%|*} rest=${fl#*|}
      local fcol=${rest%%|*} rest2=${rest#*|}
      local fch=${rest2%%|*} fcolor=${rest2#*|}
      stage_put "$frow" "$fcol" "${#fch}" "${fcolor}${fch}${RS}"
    done
  fi
  stage_emit

  # horizon: ground, not a border (§3)
  rnew; radd " $(repeat_str "$G_HORIZ" $((IW - 2))) " ""
  RC="${C_CHROME}${RP}${RS}"; rpush

  # voice line (§5.2): one sentence, never wraps; quiet while sleeping
  rnew
  local q1="“" q2="”"; [[ $TIER == A ]] && q1='"' q2='"'
  if [[ -n $VOICE_CUR ]]; then
    local vtxt="  ${q1}$(marquee "$VOICE_CUR" $((IW - 6)))${q2}"
    RP+=$vtxt
    RC+="$(osc8 "${VOICE_URL:-}" "${C_VOICE}${dimlab}${vtxt}${RS}")"
  fi
  rpush
  (( sp_v )) && blank_row

  # unauthenticated status line — permanent, above the dashboard (§5.9)
  if (( unauth )); then
    rnew; radd "  ${G_DOT_NONE} public data only · \`gh auth login\` unlocks mail, health & private contributions · refresh: 10 min" "${C_CHROME}${C_DIM}"
    RP=$(trunc "$RP" "$IW"); rpush
    blank_row
  elif (( dhint )); then
    # dense layout exists but this window/terminal can't show it — say why
    local dwhy="grow the window to 110×32 (now ${COLS}×${LINES})"
    [[ $PIX_MODE != T ]] && dwhy="terminal lacks truecolor — press d to force 256-color"
    rnew; radd "  ${G_DOT_NONE} dense layout available: $dwhy" "${C_CHROME}${C_DIM}"
    RP=$(trunc "$RP" "$IW"); rpush
  fi

  # dashboard (§5.2): happiness headline + six core bars (egg: warmth instead)
  local bw=12; (( COLS >= 80 )) && bw=20
  local frozen; frozen=$(frozen_disp "$1")
  if (( is_egg )); then
    rnew
    bar_build "${P[WARMTH]:-0}" $((bw * 2)) 0
    radd "  warmth    " "$dimlab"; RC+="$BARC"; RP+=$(repeat_str "?" $((bw * 2)))
    radd "  $(printf '%3s' "${P[WARMTH]:-0}")" ""
    rpush
    (( sp_h )) && blank_row
    local hd=$(( 7 - ${P[ACCT_DAYS]:-0} )); (( hd < 1 )) && hd=1
    rnew; radd "  hatches in ${hd}d — first contributions make the egg wiggle" "$C_CHROME"; rpush
    blank_row; blank_row
  else
    rnew
    local hnotch=""
    [[ -n ${P[CAPPED_BY]:-} ]] && hnotch=${P[HAPPY_RAW]}
    # a perfect 100 goes all green and blinks, in step with the float (§8.4)
    local hpul=0
    (( ${P[HAPPINESS]:-0} >= 100 )) && hpul=$(( 1 + (TICK / 2) % 2 ))
    bar_build "${P[HAPPINESS]:-0}" $((bw * 2)) "$frozen" "$hnotch" "$hpul"
    radd "  happiness " "$dimlab"
    radd "$G_HEART " "$C_HEARTS"
    RC+="$BARC"; RP+=$(repeat_str "?" $((bw * 2)))
    radd " " ""; RC+="$(statval "${P[HAPPINESS]:-0}" "$frozen")"; RP+="????"
    rpush
    (( sp_h )) && blank_row
    # six core bars, always the same order — spatial memory (§5.2);
    # sick swaps health in for clean while it matters (§5.3)
    local lkeys=(HUNGER ENERGY CLEAN) lnames=(hunger energy clean)
    if [[ $ANIM_STATE == sick ]]; then lkeys=(HUNGER ENERGY HEALTH) lnames=(hunger energy health); fi
    local rkeys=(MOOD SOCIAL FITNESS) rnames=(mood social fit)
    local r
    for r in 0 1 2; do
      rnew
      radd "  $(printf '%-7s' "${lnames[r]}")" "${C_CHROME}${dimlab}"
      bar_build "${P[${lkeys[r]}]:-0}" "$bw" "$frozen"
      RC+="$BARC"; RP+=$(repeat_str "?" "$bw")
      radd " " ""; RC+="$(statval "${P[${lkeys[r]}]:-0}" "$frozen")"; RP+="????"
      radd "    " ""
      radd "$(printf '%-7s' "${rnames[r]}")" "${C_CHROME}${dimlab}"
      bar_build "${P[${rkeys[r]}]:-0}" "$bw" "$frozen"
      RC+="$BARC"; RP+=$(repeat_str "?" "$bw")
      radd " " ""; RC+="$(statval "${P[${rkeys[r]}]:-0}" "$frozen")"; RP+="????"
      rpush
    done
    (( sp_b )) && blank_row
    local il
    for il in "${ins[@]}"; do
      rnew
      if [[ $il == "${ins[0]}" ]]; then radd "  ${G_SEL} $il" "$C_AMBER"
      else radd "    $il" "$C_AMBER"; fi
      rpush
    done
  fi

  # footer: the footer is the menu (§4)
  KP="" KC=""
  if [[ $self == 1 ]]; then
    key_chip f riends; key_chip s tats; key_chip r efresh; key_chip "?" help; key_chip q uit
  else
    key_chip s tats; key_chip c ompare; key_chip r efresh; KP+="[Esc] back "; KC+="${C_CHROME}[${RS}${C_BOLD}Esc${RS}${C_CHROME}]${RS} back "
  fi
  sync_cell
  push_footer "$KP" "$KC" "$SP" "$SC"
}

# ── stat detail panel (§5.4): the legibility screen ─────────────────────────
STAT_KEYS=(HUNGER ENERGY MOOD FITNESS CLEAN CURIOSITY SOCIAL WISDOM HEALTH HAPPINESS)
STAT_NAMES=(hunger energy mood fitness cleanliness curiosity social wisdom health happiness)

stat_detail_info() { # assoc_name idx → D_WHY D_SRC D_URL D_OPEN
  local -n P=$1
  local i=$2 login=${P[LOGIN]}
  D_WHY="" D_SRC="" D_URL="" D_OPEN="open"
  case ${STAT_NAMES[i]} in
    hunger)
      if (( ${P[MERGES7]:-0} > 0 )); then D_WHY="${P[MERGES7]} PRs merged in the last 7 days · newest #${P[MERGE_NUM]:-?}, ${P[MERGE_AGO_H]}h ago · each merge feeds 14, halving every 2 days"
      else D_WHY="no PRs merged in the last 7 days · each merge feeds 14, halving every 2 days — the bowl is empty"; fi
      # cached: this runs per row per frame; the label going stale at midnight
      # is cosmetic (the URL doesn't embed the date)
      [[ -z ${_DATE7:-} ]] && _DATE7=$(date_ago 7)
      D_SRC="search  is:pr author:$login is:merged merged:>${_DATE7} · medium tier · 10 min"
      D_URL="https://github.com/search?q=is%3Apr+author%3A$login+is%3Amerged&type=pullrequests"
      D_OPEN="open your merged PRs" ;;
    energy)
      D_WHY="${P[REST_GAPS]:-0} rest gap(s) ≥6h in 24h · pace ×$(( ${P[RATIO_X100]:-100} / 100 )).$(( (${P[RATIO_X100]:-100} % 100) / 10 )) of your 90d baseline"
      D_SRC="events feed gaps vs your own baseline · rewards rhythm"
      D_URL="https://github.com/$login"
      D_OPEN="open your profile" ;;
    mood)
      D_WHY="+${P[APPROVED7]:-0} approvals · ${P[MERGES7]:-0} merges · −${P[CHANGESREQ7]:-0} changes-requested (7d)"
      D_SRC="search  review:approved / review:changes_requested"
      D_URL="https://github.com/search?q=is%3Apr+author%3A$login&type=pullrequests"
      D_OPEN="open your PRs" ;;
    fitness)
      D_WHY="active ${P[ACTIVE21]:-0} of the last 21 days"
      D_SRC=$([[ $AUTH_MODE == none ]] && echo "public events feed (unauthenticated approximation)" || echo "GraphQL contributionsCollection")
      D_URL="https://github.com/$login"
      D_OPEN="open your profile" ;;
    cleanliness)
      D_WHY="${P[STALE_ISSUES]:-0} issues + ${P[STALE_PRS]:-0} PRs idle >30d on top-5 pushed repos"
      D_SRC="repo issues sort:updated-asc · −12/issue −6/PR"
      D_URL="https://github.com/issues?q=user%3A$login+is%3Aopen+sort%3Aupdated-asc"
      D_OPEN="open your stale issues" ;;
    curiosity)
      D_WHY="${P[REPOS30]:-0} repos explored (30d) · ${P[STARS14]:-0} stars given · ${P[FORKS14]:-0} forks (14d)${P[NEW_LANG]:+ · new language: ${P[NEW_LANG]}}"
      D_SRC="starred?sort=created · ForkEvents · repo languages"
      D_URL="https://github.com/$login?tab=stars"
      D_OPEN="open your stars" ;;
    social)
      D_WHY="${P[OUTBOUND7]:-0} comments/reviews on others' repos (7d) · ${P[FOLLOWING_N]:-0} friends followed"
      D_SRC="public events: outbound comments & reviews (7·√n) · following (1 pt each, ≤20)"
      D_URL="https://github.com/$login"
      D_OPEN="open your profile" ;;
    wisdom)
      D_WHY="${P[REVIEWS_TOTAL]:-0} reviews given · ${P[NLANGS]:-0} languages · est. ${P[CREATED_YEAR]}"
      D_SRC="search  is:pr reviewed-by:$login · log-scale, ~monotonic"
      D_URL="https://github.com/search?q=is%3Apr+reviewed-by%3A$login&type=pullrequests"
      D_OPEN="open PRs you reviewed" ;;
    health)
      D_WHY="Dependabot alerts weighted crit 20 · high 10 · moderate 5"
      D_SRC="dependabot alerts API — self only, needs auth"
      D_URL="https://github.com/$login?tab=repositories"
      D_OPEN="open your repos" ;;
    happiness)
      D_WHY="weighted composite of the nine · misery cap: any survival stat <20 caps at 60"
      D_SRC="0.28·hunger 0.24·mood 0.18·energy 0.10·social …"
      D_URL="" ;;
  esac
}

draw_stats() { # assoc_name self
  local -n P=$1
  local self=$2
  IW=$((COLS - 2))
  SCREEN=()
  push_title "stats · ${P[NAME]}" "" ""
  blank_row
  local bw=12 i frozen=0
  [[ ${P[HIB]:-0} == 1 ]] && frozen=1
  for i in "${!STAT_KEYS[@]}"; do
    local nm=${STAT_NAMES[i]} v=${P[${STAT_KEYS[i]}]:-}
    [[ $i == 9 ]] && { rnew; radd "   $(repeat_str "$B_H" 37)" "$C_CHROME"; rpush; }
    rnew
    local sel=" "
    (( i == SEL_STAT )) && sel=$G_SEL
    radd " $sel " "$C_INK"
    radd "$(printf '%-12s' "$nm")" "$([[ $i -eq $SEL_STAT ]] && echo -n "$C_BOLD" || echo -n "$C_CHROME")"
    if [[ $nm == health && -z $v ]]; then
      radd "─ private · by design" "${C_CHROME}${C_DIM}"
      rpush; continue
    fi
    bar_build "${v:-0}" "$bw" "$frozen"
    RC+="$BARC"; RP+=$(repeat_str "?" "$bw")
    radd " " ""; RC+="$(statval "${v:-0}" "$frozen")"; RP+="????"
    case $nm in
      fitness)   radd "   · ${P[ACTIVE21]:-0} of last 21 days" "$C_CHROME" ;;
      wisdom)    (( ${v:-0} >= 60 )) && radd "   · (o-o) earned" "$C_CHROME" ;;
      happiness) [[ -n ${P[CAPPED_BY]:-} ]] && radd "  ⚠ capped — ${P[CAPPED_BY]} ${P[CAPPED_VAL]} < 20" "$C_AMBER" ;;
    esac
    rpush
    if (( i == SEL_STAT )); then
      stat_detail_info "$1" "$i"
      rnew; radd "    $(trunc "$D_WHY" $((IW - 6)))" ""; rpush
      rnew; radd "    src: $(trunc "$D_SRC" $((IW - 10)))" "${C_CHROME}${C_DIM}"; rpush
    fi
  done
  while (( ${#SCREEN[@]} < LINES - 1 )); do blank_row; done
  KP="" KC=""
  key_chip jk " select"; key_chip "↵" " open on github"; key_chip Esc " back"
  sync_cell; push_footer "$KP" "$KC" "$SP" "$SC"
}

# ── friends list (§5.5) ─────────────────────────────────────────────────────
draw_friends() {
  IW=$((COLS - 2))
  SCREEN=()
  push_title "friends · following ${#FR_LOGINS[@]}" "" ""
  blank_row
  if (( ${#FR_LOGINS[@]} == 0 )); then
    blank_row; blank_row
    rnew; radd "   Follow someone on GitHub and their pet appears here." "$C_CHROME"; rpush
    rnew; radd "   A friend's pet is computed from their public account —" "$C_CHROME"; rpush
    rnew; radd "   nothing to invite, nothing to sync." "$C_CHROME"; rpush
  else
    local i
    for i in "${!FR_SORTED[@]}"; do
      (( ${#SCREEN[@]} >= LINES - 2 )) && break
      local login=${FR_SORTED[i]} row=${FRROW[${FR_SORTED[i]}]:-}
      rnew
      local sel=" "; (( i == SEL_FRIEND )) && sel=$G_SEL
      radd " $sel " ""
      radd "$(printf '%-14s' "$(trunc "$login" 14)")" "$([[ $i -eq $SEL_FRIEND ]] && echo -n "$C_BOLD")"
      if [[ -z $row ]]; then
        radd "···" "${C_CHROME}${C_DIM}"   # fills in as responses land (§5.5)
      else
        local pname=${row%%|*} rest=${row#*|}
        local mini=${rest%%|*} rest2=${rest#*|}
        local c256=${rest2%%|*} rest3=${rest2#*|}
        local happy=${rest3%%|*} rest4=${rest3#*|}
        local state=${rest4%%|*}
        radd "$(printf '%-10s' "$pname")" ""
        radd "$(padw "$mini" 6)" "$(fg "$c256")"
        case $state in
          hib:*)  radd "${G_ZZZ} hibernating · ${state#hib:}d" "$C_ICE" ;;
          egg:*)  radd "egg · hatches in ${state#egg:}d" "$C_MAILC" ;;
          *)      radd "$G_HEART " "$C_HEARTS"; RC+="$(statval "$happy" 0)"; RP+="????" ;;
        esac
      fi
      rpush
    done
  fi
  while (( ${#SCREEN[@]} < LINES - 1 )); do blank_row; done
  KP="" KC=""
  key_chip jk " move"; key_chip "↵" " visit"; key_chip c ompare; key_chip Esc " back"
  sync_cell; push_footer "$KP" "$KC" "$SP" "$SC"
}

# ── compare view (§5.7): friendly rivalry, not a leaderboard ────────────────
draw_compare() { # me_assoc friend_assoc
  local -n CM=$1
  local -n CF=$2
  IW=$((COLS - 2))
  local LW=$(( IW / 2 - 1 ))
  local RW=$(( IW - LW - 1 ))
  SCREEN=()
  # split title
  local lt=" you · ${CM[NAME]} " rt=" @${CF[LOGIN]} · ${CF[NAME]} "
  local ld=$(( LW - ${#lt} - 1 )); (( ld < 1 )) && ld=1
  local rd=$(( RW - ${#rt} - 1 )); (( rd < 1 )) && rd=1
  SCREEN+=("${C_CHROME}${B_TL}${B_H}${RS}${C_BOLD}${lt}${RS}${C_CHROME}$(repeat_str "$B_H" "$ld")┬${B_H}${RS}${C_BOLD}${rt}${RS}${C_CHROME}$(repeat_str "$B_H" "$rd")${B_TR}${RS}")

  # both pets, idle frames only (§5.7), bottom-aligned in a 9-row half-stage
  local stage_h=9
  (( LINES < 24 )) && stage_h=$(( LINES - 12 )); (( stage_h < 4 )) && stage_h=4
  local -a LP=() RP2=()
  local lw=0 rw=0 lh rh
  # §5.7: idle frames only — never the live ANIM_FRAME (sick/sleep/eat/celebrate),
  # which would make "you" asymmetric with the always-idle friend and drag the
  # stretcher theater into a comparison. Hibernating self shows a cocoon, like the friend.
  if [[ ${CM[HIB]:-0} == 1 ]]; then
    cocoon_frame $(( (TICK / 4) % 2 )) ""
    LP=("${SPCOMP_COL[@]}"); lh=${#LP[@]}; lw=0
    local ll; for ll in "${SPCOMP_PLAIN[@]}"; do (( ${#ll} > lw )) && lw=${#ll}; done
  else
    pet_compose "$1" idle_1 0 0
    LP=("${PET_LINES[@]}"); lw=$PET_W; lh=$PET_H
  fi
  local ffr=idle_1; [[ ${CF[HIB]:-0} == 1 ]] && ffr=idle_1
  if [[ ${CF[HIB]:-0} == 1 ]]; then
    cocoon_frame $(( (TICK / 4) % 2 )) ""
    RP2=("${SPCOMP_COL[@]}"); rh=${#RP2[@]}; rw=0
    local l; for l in "${SPCOMP_PLAIN[@]}"; do (( ${#l} > rw )) && rw=${#l}; done
  else
    pet_compose "$2" "$ffr" 0 0
    RP2=("${PET_LINES[@]}"); rw=$PET_W; rh=$PET_H
  fi
  local r
  for ((r=0; r<stage_h; r++)); do
    local li=$(( r - (stage_h - lh) )) ri=$(( r - (stage_h - rh) ))
    local lc="" lplen=0 rc="" rplen=0
    if (( li >= 0 && li < lh )); then lc=${LP[li]}; lplen=$lw; fi
    if (( ri >= 0 && ri < rh )); then rc=${RP2[ri]}; rplen=$rw; fi
    local lpad=$(( (LW - lplen) / 2 )) rpad=$(( (RW - rplen) / 2 ))
    (( lpad < 0 )) && lpad=0; (( rpad < 0 )) && rpad=0
    local lfill=$(( LW - lpad - lplen )) rfill=$(( RW - rpad - rplen ))
    (( lfill < 0 )) && lfill=0; (( rfill < 0 )) && rfill=0
    SCREEN+=("${C_CHROME}${B_V}${RS}$(repeat_str " " $lpad)${lc}$(repeat_str " " $lfill)${C_CHROME}${B_V}${RS}$(repeat_str " " $rpad)${rc}$(repeat_str " " $rfill)${C_CHROME}${B_V}${RS}")
  done
  # split horizon
  SCREEN+=("${C_CHROME}${B_V} $(repeat_str "$G_HORIZ" $((LW - 2))) ${B_V} $(repeat_str "$G_HORIZ" $((RW - 2))) ${B_V}${RS}")

  # paired stat rows; ◂ marks the higher value; health excluded (§5.7)
  local keys=(HAPPINESS HUNGER ENERGY FITNESS SOCIAL CLEAN)
  local names=(happy hunger energy fit social clean)
  local bw=10 i
  local mf=0 ff=0
  [[ ${CM[HIB]:-0} == 1 ]] && mf=1
  [[ ${CF[HIB]:-0} == 1 ]] && ff=1
  for i in "${!keys[@]}"; do
    local mv=${CM[${keys[i]}]:-0} fv=${CF[${keys[i]}]:-0}
    local lmark="  " rmark="  "
    (( mv > fv )) && lmark="${C_GREEN}${G_CMPW}${RS} "
    (( fv > mv )) && rmark="${C_GREEN}${G_CMPW}${RS} "
    bar_build "$mv" "$bw" "$mf"; local lbar=$BARC
    bar_build "$fv" "$bw" "$ff"; local rbar=$BARC
    local lrow_p="  $(printf '%-7s' "${names[i]}")??????????? ??? ? " # width tracking
    local lrow="  ${C_CHROME}$(printf '%-7s' "${names[i]}")${RS}${lbar} $(statval "$mv" "$mf") ${lmark}"
    local rrow="  ${C_CHROME}$(printf '%-7s' "${names[i]}")${RS}${rbar} $(statval "$fv" "$ff") ${rmark}"
    local lvis=$(( 2 + 7 + bw + 1 + 4 + 1 + 2 )) rvis=$(( 2 + 7 + bw + 1 + 4 + 1 + 2 ))
    local lfill=$(( LW - lvis )) rfill=$(( RW - rvis ))
    (( lfill < 0 )) && lfill=0; (( rfill < 0 )) && rfill=0
    SCREEN+=("${C_CHROME}${B_V}${RS}${lrow}$(repeat_str " " $lfill)${C_CHROME}${B_V}${RS}${rrow}$(repeat_str " " $rfill)${C_CHROME}${B_V}${RS}")
  done
  # medals row
  local mm ff2
  mm=$(compare_medal_str "${CM[MEDALS_RAW]:-}" "${CM[MEDALS_OK]:-0}")
  ff2=$(compare_medal_str "${CF[MEDALS_RAW]:-}" "${CF[MEDALS_OK]:-0}")
  local mmv rmv                                   # fill must count the DISPLAYED
  mmv=$(trunc "$mm" $((LW - 11)))                  # (truncated) string, not the raw
  rmv=$(trunc "$ff2" $((RW - 11)))                 # one — else the border misaligns
  local lrow="  ${C_CHROME}medals ${RS}${C_MAILC}${mmv}${RS}"
  local rrow="  ${C_CHROME}medals ${RS}${C_MAILC}${rmv}${RS}"
  local lfill=$(( LW - 9 - ${#mmv} )); (( lfill < 0 )) && lfill=0
  local rfill=$(( RW - 9 - ${#rmv} )); (( rfill < 0 )) && rfill=0
  SCREEN+=("${C_CHROME}${B_V}${RS}${lrow}$(repeat_str " " $lfill)${C_CHROME}${B_V}${RS}${rrow}$(repeat_str " " $rfill)${C_CHROME}${B_V}${RS}")

  while (( ${#SCREEN[@]} < LINES - 1 )); do
    SCREEN+=("${C_CHROME}${B_V}${RS}$(repeat_str " " $LW)${C_CHROME}${B_V}${RS}$(repeat_str " " $RW)${C_CHROME}${B_V}${RS}")
  done
  # footer literally states the stance (§5.7)
  local stance="friendly rivalry, not a leaderboard "
  KP="" KC=""; key_chip Esc " back"
  local dashes=$(( IW - ${#KP} - ${#stance} - 4 )); (( dashes < 1 )) && dashes=1
  SCREEN+=("${C_CHROME}${B_BL}${RS} ${KC} ${C_CHROME}$(repeat_str "$B_H" "$dashes")${RS}${C_CHROME}${C_DIM} ${stance}${RS}${C_CHROME}${B_H}${B_BR}${RS}")
}

compare_medal_str() { # raw ok
  [[ $2 != 1 || -z $1 ]] && { printf '—'; return; }
  local out="" m IFS=';'
  for m in $1; do
    out+="[$(medal_code "${m%%|*}")$(sup_tier "${m##*|}")]"
  done
  unset IFS
  printf '%s' "$out"
}

# ── help overlay (§5.8): centered card over the main screen ─────────────────
overlay_help() {
  local -a card=(
    "┌──────────────── gitagotchi · v$VERSION ────────────────┐"
    "│                                                      │"
    "│   f  friends list          s  stat detail            │"
    "│   g  activity graph        e  feed log               │"
    "│   c  compare (on friend)   r  refresh (tier-aware)   │"
    "│   ↵  open / visit          jk ↑↓  move               │"
    "│   ⇥  cycle the rows        d  dense ↔ cozy layout    │"
    "│   Esc back / clear                                   │"
    "│   q  quit                                            │"
    "│                                                      │"
    "│   your pet is computed from your GitHub account —    │"
    "│   nothing is stored, nothing is sent anywhere.       │"
    "│                                                      │"
    "│              Esc or ? closes this card               │"
    "└──────────────────────────────────────────────────────┘"
  )
  if [[ $TIER == A ]]; then
    card=("${card[@]//┌/+}"); card=("${card[@]//┐/+}"); card=("${card[@]//└/+}")
    card=("${card[@]//┘/+}"); card=("${card[@]//─/-}"); card=("${card[@]//│/|}")
    card=("${card[@]//↵/E}"); card=("${card[@]//↑↓/ar}")
  fi
  local ch=${#card[@]} cw=${#card[0]}
  local top=$(( (LINES - ch) / 2 )) left=$(( (COLS - cw) / 2 ))
  (( top < 1 )) && top=1; (( left < 0 )) && left=0
  local i
  for ((i=0; i<ch; i++)); do
    (( top + i >= ${#SCREEN[@]} )) && break
    SCREEN[top + i]="$(repeat_str " " $left)${C_INK}${card[i]}${RS}"
  done
}

# ── window too small (§5.9) ─────────────────────────────────────────────────
draw_toosmall() { # petname
  SCREEN=()
  local -a card=(
    "┌────────────────────────┐"
    "│   (o.o)                │"
    "│   $(printf '%-20s' "$(trunc "$1 needs room:" 20)") │"
    "│   60×20 · now ${COLS}×${LINES}$(repeat_str " " $((9 - ${#COLS} - ${#LINES})))│"
    "└────────────────────────┘"
  )
  [[ $TIER == A ]] && { card=("${card[@]//─/-}"); card=("${card[@]//│/|}")
    card=("${card[@]//┌/+}"); card=("${card[@]//┐/+}"); card=("${card[@]//└/+}"); card=("${card[@]//┘/+}")
    card=("${card[@]//×/x}"); }
  local top=$(( (LINES - 5) / 2 )) left=$(( (COLS - 26) / 2 ))
  (( top < 0 )) && top=0; (( left < 0 )) && left=0
  local i
  for ((i=0; i<LINES-1; i++)); do SCREEN+=(""); done
  for i in "${!card[@]}"; do
    (( top + i < ${#SCREEN[@]} )) && SCREEN[top + i]="$(repeat_str " " $left)${card[i]}"
  done
}
