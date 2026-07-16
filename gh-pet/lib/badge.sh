# gitagotchi — lib/badge.sh
# `gh-pet badge` (plan.md §11): the pet as a self-contained SVG for README
# embedding. Each pixel of the composed 24×18 grid becomes a <rect> — no
# half-block squeeze, so this is the sprite at full authored fidelity.
# The output is deterministic for a given derived state (no clocks, no
# RANDOM, TICK unset → canonical wag/gurney phases), so a commit-if-changed
# cron only commits when the pet itself changed. Blink is a CSS overlay of
# just the pixels that differ — GitHub's camo proxy keeps SVG CSS animations.

BADGE_BG="#0d1117" BADGE_BORDER="#30363d" BADGE_MUTED="#8b949e" BADGE_DIM="#484f58"
BADGE_SCALE=6

declare -a PIXGRID=()

_badge_rects() { # gridname → run-length <rect> rows appended to BADGE_OUT
  local -n GG=$1
  local y row x x0 c rgb
  for y in "${!GG[@]}"; do
    row=${GG[y]}
    x=0
    while (( x < ${#row} )); do
      c=${row:x:1}
      if [[ $c == "." || -z ${PC[$c]:-} ]]; then x=$((x + 1)); continue; fi
      x0=$x
      while (( x < ${#row} )) && [[ ${row:x:1} == "$c" ]]; do x=$((x + 1)); done
      rgb=${PC[$c]}
      BADGE_OUT+="<rect x=\"$x0\" y=\"$y\" width=\"$((x - x0))\" height=\"1\" fill=\"rgb(${rgb//;/,})\"/>"
    done
  done
}

_badge_blink_rects() { # open_grid blink_grid → only the differing pixels
  local -n GA=$1
  local -n GB=$2
  local y ra rb x x0 c rgb fill
  BADGE_BLINKS=0
  for y in "${!GA[@]}"; do
    ra=${GA[y]}; rb=${GB[y]:-}
    [[ $ra == "$rb" ]] && continue
    x=0
    while (( x < ${#rb} )); do
      if [[ ${ra:x:1} == "${rb:x:1}" ]]; then x=$((x + 1)); continue; fi
      c=${rb:x:1}; x0=$x
      while (( x < ${#rb} )) && [[ ${rb:x:1} == "$c" && ${ra:x:1} != "$c" ]]; do x=$((x + 1)); done
      if [[ $c == "." || -z ${PC[$c]:-} ]]; then fill=$BADGE_BG
      else rgb=${PC[$c]}; fill="rgb(${rgb//;/,})"; fi
      BADGE_OUT+="<rect x=\"$x0\" y=\"$y\" width=\"$((x - x0))\" height=\"1\" fill=\"$fill\"/>"
      BADGE_BLINKS=$((BADGE_BLINKS + 1))
    done
  done
}

# frame follows the derived state, same precedence as anim_update
# (gh-pet: HIB > … > sick > … > sleep): an unwell pet reads as sick, not
# asleep, and unknown (unauthenticated) health never triggers sick. Extracted
# so the precedence is unit-testable in isolation (tests/run.sh).
badge_frame() { # assoc_name → BADGE_FRAME BADGE_BLINKABLE BADGE_FAINT
  local -n _BF=$1
  BADGE_FRAME=idle_1 BADGE_BLINKABLE=1 BADGE_FAINT=0
  if [[ ${_BF[HIB]:-0} == 1 ]]; then BADGE_FRAME=hibernate_1 BADGE_BLINKABLE=0
  elif [[ -n ${_BF[HEALTH]:-} ]] && (( ${_BF[HEALTH]} < 40 )); then
    BADGE_FRAME=sick_1 BADGE_BLINKABLE=0 BADGE_FAINT=1
  elif [[ ${_BF[SLEEPING]:-0} == 1 ]]; then BADGE_FRAME=sleep_1 BADGE_BLINKABLE=0
  fi
}

badge_render() { # assoc_name → SVG on stdout
  local -n BP=$1

  badge_frame "$1"
  local frame=$BADGE_FRAME blinkable=$BADGE_BLINKABLE faint=$BADGE_FAINT

  # canonical phases: the tail plants, a critical pet arrives settled on the
  # gurney — and nothing time-shaped leaks into the file
  unset TICK

  local om=$PIX_MODE
  PIX_MODE=T
  PIX_CAPTURE=1
  local -a G0=() G1=()
  if [[ ${BP[STAGE]:-} == egg ]]; then
    # eggs render the shared pixel egg, tinted by the owner's linguist color
    PIX_BEARD_RGB=${BP[BEARD_RGB]:-}
    pix_palette egg "${BP[COLOR_HEX]}" 0
    pix_render egg idle_1 0
    G0=("${PIXGRID[@]}")
    blinkable=0
  else
    pet_compose "$1" "$frame" 0 "$faint"
    G0=("${PIXGRID[@]}")
    if (( blinkable )); then
      pet_compose "$1" "$frame" 1 "$faint"
      G1=("${PIXGRID[@]}")
    fi
  fi
  PIX_CAPTURE=0
  PIX_MODE=$om

  local pw=${#G0[0]} ph=${#G0[@]}
  local sc=$BADGE_SCALE
  local sw=$((pw * sc)) sh=$((ph * sc))

  # the identity line — hibernation/sleep named, like the terminal card.
  # Hibernation supersedes sleep: a months-quiet pet is also technically
  # "asleep" (>6h), but only one dormancy word belongs on the card.
  local sub="the ${BP[SPECIES_LABEL]:-${BP[SPECIES]}} · ${BP[STAGE]:-?} · @${BP[LOGIN]:-?}"
  [[ ${BP[STAGE]:-} == egg ]] && sub="an egg · @${BP[LOGIN]:-?}"
  if [[ ${BP[HIB]:-0} == 1 ]]; then sub+=" · hibernating"
  elif [[ ${BP[SLEEPING]:-0} == 1 ]]; then sub+=" · asleep"; fi

  # the card fits the WIDEST element — often the subtitle, not the sprite;
  # monospace advance ≈ 0.6em, so ~6.6px per char at font-size 11 (+pad).
  # Undersizing clipped the identity line off the right edge on long logins.
  local sub_w=$(( ${#sub} * 66 / 10 + 34 ))
  local W=$((sw + 64)); (( W < 300 )) && W=300; (( W < sub_w )) && W=$sub_w
  local sx=$(( (W - sw) / 2 )) sy=22
  local name_y=$((sy + sh + 30))
  local sub_y=$((name_y + 19))
  local bar_y=$((sub_y + 16))
  local H=$((bar_y + 34))

  # happiness meter wears the vitals gradient colors
  local hp=${BP[HAPPINESS]:-0} bcol="#3fb950"
  (( hp < 70 )) && bcol="#d29922"
  (( hp < 40 )) && bcol="#f85149"
  local bw=180 bfill=$((hp * 180 / 100))
  local bx=$(( (W - bw - 44) / 2 + 14 ))

  local BADGE_OUT="" BADGE_BLINKS=0
  _badge_rects G0
  local pet_rects=$BADGE_OUT
  local blink_rects=""
  if (( blinkable && ${#G1[@]} )); then
    BADGE_OUT=""
    _badge_blink_rects G0 G1
    blink_rects=$BADGE_OUT
    (( BADGE_BLINKS == 0 )) && blink_rects=""   # wired pets don't blink
  fi

  printf '<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s" viewBox="0 0 %s %s" role="img" aria-label="%s, a gitagotchi">\n' \
    "$W" "$H" "$W" "$H" "${BP[NAME]:-pet}"
  printf '<title>%s — @%s&#8217;s gitagotchi</title>\n' "${BP[NAME]:-pet}" "${BP[LOGIN]:-?}"
  if [[ -n $blink_rects ]]; then
    printf '<style>#blink{opacity:0;animation:bl 4.6s step-end infinite}@keyframes bl{0%%,91%%{opacity:0}91.01%%,96%%{opacity:1}96.01%%,100%%{opacity:0}}</style>\n'
  fi
  printf '<rect x="0.5" y="0.5" width="%s" height="%s" rx="8" fill="%s" stroke="%s"/>\n' \
    "$((W - 1))" "$((H - 1))" "$BADGE_BG" "$BADGE_BORDER"
  printf '<g transform="translate(%s,%s) scale(%s)" shape-rendering="crispEdges">\n' "$sx" "$sy" "$sc"
  printf '<g>%s</g>\n' "$pet_rects"
  [[ -n $blink_rects ]] && printf '<g id="blink">%s</g>\n' "$blink_rects"
  printf '</g>\n'
  printf '<text x="%s" y="%s" text-anchor="middle" font-family="ui-monospace,SFMono-Regular,Menlo,Consolas,monospace" font-size="16" font-weight="bold" fill="%s">%s</text>\n' \
    "$((W / 2))" "$name_y" "${BP[COLOR_HEX]:-#dea584}" "${BP[NAME]:-pet}"
  printf '<text x="%s" y="%s" text-anchor="middle" font-family="ui-monospace,SFMono-Regular,Menlo,Consolas,monospace" font-size="11" fill="%s">%s</text>\n' \
    "$((W / 2))" "$sub_y" "$BADGE_MUTED" "$sub"
  printf '<text x="%s" y="%s" text-anchor="end" font-family="ui-monospace,SFMono-Regular,Menlo,Consolas,monospace" font-size="11" fill="#f778ba">&#9829;</text>\n' \
    "$((bx - 6))" "$((bar_y + 8))"
  printf '<rect x="%s" y="%s" width="%s" height="8" rx="4" fill="#21262d"/>\n' "$bx" "$bar_y" "$bw"
  (( bfill > 0 )) && printf '<rect x="%s" y="%s" width="%s" height="8" rx="4" fill="%s"/>\n' "$bx" "$bar_y" "$bfill" "$bcol"
  printf '<text x="%s" y="%s" font-family="ui-monospace,SFMono-Regular,Menlo,Consolas,monospace" font-size="11" fill="%s">%s</text>\n' \
    "$((bx + bw + 8))" "$((bar_y + 8))" "$BADGE_MUTED" "$hp"
  printf '<text x="%s" y="%s" text-anchor="end" font-family="ui-monospace,SFMono-Regular,Menlo,Consolas,monospace" font-size="9" fill="%s">gitagotchi</text>\n' \
    "$((W - 12))" "$((H - 10))" "$BADGE_DIM"
  printf '</svg>\n'
}
