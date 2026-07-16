# gitagotchi — lib/derive.sh
# Runs the jq derive program over cached API data, then finishes the
# seed-derived identity traits in bash (plan.md §2).

DERIVE_INPUTS=(user repos events merged approved changesreq reviewedby starred
               stale alerts calendar notifications medals orgs following)

_derive_args() { # login now → fills DARGS[]
  local login=$1 now=$2 f
  local dir="$CACHE_ROOT/$login"
  DARGS=(-r --arg now "$now" --arg login "$login")
  for f in "${DERIVE_INPUTS[@]}"; do
    if [[ -s $dir/$f.json ]] && jq -e . "$dir/$f.json" >/dev/null 2>&1; then
      DARGS+=(--slurpfile "$f" "$dir/$f.json")
    else
      DARGS+=(--argjson "$f" null)
    fi
  done
}

derive_state() { # login → writes $CACHE_ROOT/$login/state.env
  local login=$1; local dir="$CACHE_ROOT/$login"
  mkdir -p "$dir"
  local -a DARGS
  _derive_args "$login" "$(date +%s)"
  if jq -n "${DARGS[@]}" -f "$LIB_DIR/stats.jq" > "$dir/.state.tmp" 2>"$dir/.state.err"; then
    mv "$dir/.state.tmp" "$dir/state.env"
  else
    rm -f "$dir/.state.tmp"
    return 1
  fi
}

# Sparkline history (ux-spec §9.3): nothing is stored, so history is
# DERIVED — the same pure f(github_data, wall_clock) evaluated hourly at
# t−29h … t against the same cached data. Same invariant, real history.
# Hourly spacing (not the 10-min refresh cadence) because stats move on
# day scales — a 5h window rendered thirty flat columns. The dense vitals
# rows bucket the 30 points into a 5-cell sparkline; the expanded stat
# detail shows all 30.
HIST_KEYS=(HUNGER ENERGY MOOD FITNESS CLEAN CURIOSITY SOCIAL WISDOM HEALTH HAPPINESS)
derive_history() { # login → writes $CACHE_ROOT/$login/hist.env
  local login=$1; local dir="$CACHE_ROOT/$login"
  local now k key line
  now=$(date +%s)
  local -A hv=()
  local -a DARGS
  for ((k=29; k>=0; k--)); do
    _derive_args "$login" $((now - k * 3600))
    while IFS= read -r line; do
      [[ $line =~ ^([A-Z]+)=\'(.*)\'$ ]] || continue
      # keep unknowns unknown: an unauthenticated pet emits HEALTH='' — faking it
      # to 0 would paint a flat-critical health sparkline instead of "no data".
      [[ -z ${BASH_REMATCH[2]} ]] && continue
      hv[${BASH_REMATCH[1]}]+="${BASH_REMATCH[2]} "
    done < <(jq -n "${DARGS[@]}" -f "$LIB_DIR/stats.jq" 2>/dev/null \
             | grep -E '^(HUNGER|ENERGY|MOOD|FITNESS|CLEAN|CURIOSITY|SOCIAL|WISDOM|HEALTH|HAPPINESS)=')
  done
  {
    for key in "${HIST_KEYS[@]}"; do
      printf "HIST_%s='%s'\n" "$key" "${hv[$key]% }"
    done
  } > "$dir/hist.env"
}

# load_state ASSOC login — read state.env into an assoc array, then derive the
# identity layer (species, name, color, pattern, accessory) from the seed.
load_state() {
  local -n A=$1
  local login=$2; local dir="$CACHE_ROOT/$login"
  [[ -f $dir/state.env ]] || return 1
  local line
  while IFS= read -r line; do
    [[ $line =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]] || continue
    eval "A[${BASH_REMATCH[1]}]=${BASH_REMATCH[2]}"
  done < "$dir/state.env"
  if [[ -f $dir/hist.env ]]; then
    while IFS= read -r line; do
      [[ $line =~ ^(HIST_[A-Z]+)=(.*)$ ]] || continue
      eval "A[${BASH_REMATCH[1]}]=${BASH_REMATCH[2]}"
    done < "$dir/hist.env"
  fi

  # identity is a pure function of the numeric user id (plan.md §2).
  # Species indexes into the bundled pixel-species list (sprites-pixel.txt);
  # the ASCII tier renders the nearest §6 body for the same species identity.
  seed_init "${A[ID]:-0}"
  if (( ${#PIX_SPECIES[@]} > 0 )); then
    A[SPECIES]=${PIX_SPECIES[SEED[0] % ${#PIX_SPECIES[@]}]}
    A[SPECIES_ASCII]=$(pix_ascii_fallback "${A[SPECIES]}")
    A[MINI]=$(pix_mini "${A[SPECIES]}")
  else
    A[SPECIES]=$(pick_species)
    A[SPECIES_ASCII]=${A[SPECIES]}
    A[MINI]=$(sprite_mini "${A[SPECIES]}")
  fi
  # displayed taxonomy: the gallery's invented species name ("Randu", not
  # "raccoon"); the animal id stays internal for sprite/palette lookups
  A[SPECIES_LABEL]=${PIXNAME[${A[SPECIES]}]:-${A[SPECIES]}}

  # preview knob: GITAGOTCHI_PRETEND_QUIET=<days> pretends you've been gone —
  # see drowsy (21+), hibernation (30+), cobwebs (90+) without waiting months.
  # Session-only theater; unset it and the real derived state is back.
  if [[ ${GITAGOTCHI_PRETEND_QUIET:-} =~ ^[0-9]+$ ]]; then
    A[DAYS_QUIET]=$GITAGOTCHI_PRETEND_QUIET
    A[HOURS_QUIET]=$(( GITAGOTCHI_PRETEND_QUIET * 24 ))
    A[HIB]=0; A[DROWSY]=0; A[SLEEPING]=0
    if (( GITAGOTCHI_PRETEND_QUIET >= 30 )); then A[HIB]=1
    elif (( GITAGOTCHI_PRETEND_QUIET >= 21 )); then A[DROWSY]=1
    elif (( GITAGOTCHI_PRETEND_QUIET * 24 >= 6 )); then A[SLEEPING]=1
    fi
  fi
  # preview knob: GITAGOTCHI_PRETEND_VISITORS="mona defunkt" stages the
  # social cameo without waiting for a real last-hour interaction
  [[ -n ${GITAGOTCHI_PRETEND_VISITORS:-} ]] && A[VISITORS]=$GITAGOTCHI_PRETEND_VISITORS
  # preview knob: GITAGOTCHI_PRETEND_CLEAN=<0-100> stages the mess level
  [[ ${GITAGOTCHI_PRETEND_CLEAN:-} =~ ^[0-9]+$ ]] && A[CLEAN]=$GITAGOTCHI_PRETEND_CLEAN
  # preview knob: GITAGOTCHI_PRETEND_WISDOM=<0-100> stages the beard length
  [[ ${GITAGOTCHI_PRETEND_WISDOM:-} =~ ^[0-9]+$ ]] && A[WISDOM]=$GITAGOTCHI_PRETEND_WISDOM
  # preview knob: GITAGOTCHI_PRETEND_OUTBOUND=<n> stages review duty (the spear)
  [[ ${GITAGOTCHI_PRETEND_OUTBOUND:-} =~ ^[0-9]+$ ]] && A[OUTBOUND7]=$GITAGOTCHI_PRETEND_OUTBOUND
  A[NAME]=$(gen_name)
  # personalization: your own pet is always Zeruko (friends keep their derived
  # names). Skipped under --fixtures so the test personas derive normally.
  [[ -z ${FIXDIR:-} ]] && same_login "$login" "${ME:-}" && A[NAME]=Zeruko
  A[BEARD_RGB]=$(beard_color_for "${A[CREATED]:-}" "${A[ID]:-0}")
  A[COLOR_HEX]=$(pet_color_hex "${A[TOP_LANG]:-}")
  A[COLOR256]=$(hex_to_256 "${A[COLOR_HEX]}")
  A[PATTERN]=$(pattern_for_lang "${A[SECOND_LANG]:-}")
  A[ACCESSORY]=$(pick_accessory "${A[ADMIN_OR_PRO]:-false}" "${A[ORG_MEMBER]:-false}" \
                                "${A[HIREABLE]:-false}" "${A[BIO_SET]:-false}")
  return 0
}
