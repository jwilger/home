# Claude Code status line, styled after the Starship prompt (Catppuccin Mocha).
# Claude Code pipes session JSON on stdin and draws each output line as a row.
# Every segment is optional, and the script must always exit 0: a failing
# status line command leaves Claude Code with a blank row.
#   line 1: directory, NixOS mark and arrow, git branch
#   line 2: model, context %, session cost, 5h/7d limits, spend limit
input="$(cat)"

blue='137;180;250'
lavender='180;190;254'
green='166;227;161'
mauve='203;166;247'
yellow='249;226;175'
red='243;139;168'
peach='250;179;135'
overlay='108;112;134'

field() { jq -r "$1 // empty" <<<"$input" 2>/dev/null || true; }
fg() { printf '\033[38;2;%sm' "$1"; }
bold() { printf '\033[1;38;2;%sm' "$1"; }
reset() { printf '\033[0m'; }

# label percent [resets_at_epoch date_format]
usage() {
  local label="$1" pct="$2" resets="${3:-}" format="${4:-}" rounded color
  if [[ -z "$pct" ]]; then
    return 0
  fi
  rounded="$(LC_ALL=C printf '%.0f' "$pct" 2>/dev/null || true)"
  if [[ -z "$rounded" ]]; then
    return 0
  fi
  if ((rounded >= 80)); then
    color="$red"
  elif ((rounded >= 50)); then
    color="$yellow"
  else
    color="$green"
  fi
  printf ' '
  fg "$overlay"
  printf '%s ' "$label"
  fg "$color"
  printf '%s%%' "$rounded"
  reset
  if [[ -n "$resets" ]]; then
    fg "$overlay"
    printf ' (%s)' "$(date -d "@${resets%.*}" "+$format" 2>/dev/null || true)"
    reset
  fi
}

first_line() {
  local dir branch=""
  dir="$(field '.workspace.current_dir // .cwd')"
  if [[ -n "$dir" ]]; then
    branch="$(git -C "$dir" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null || true)"
  fi
  if [[ -n "${HOME:-}" && "$dir" == "$HOME"* ]]; then
    dir="~${dir#"$HOME"}"
  fi
  bold "$blue"
  printf '\356\227\276 '
  bold "$lavender"
  printf '%s ' "$dir"
  bold "$blue"
  printf '\357\214\223 '
  bold "$green"
  printf '\342\236\234'
  reset
  if [[ -n "$branch" ]]; then
    fg "$mauve"
    printf ' \356\234\245 %s' "$branch"
    reset
  fi
}

second_line() {
  local model cost used limit label
  model="$(field .model.display_name)"
  if [[ -n "$model" ]]; then
    printf ' '
    fg "$yellow"
    printf '%s' "$model"
    reset
  fi
  usage ctx "$(field .context_window.used_percentage)"
  cost="$(field .cost.total_cost_usd)"
  if [[ -n "$cost" ]]; then
    printf ' '
    fg "$peach"
    LC_ALL=C printf '$%.2f' "$cost" 2>/dev/null || true
    reset
  fi
  usage 5h "$(field .rate_limits.five_hour.used_percentage)" \
    "$(field .rate_limits.five_hour.resets_at)" '%H:%M'
  usage 7d "$(field .rate_limits.seven_day.used_percentage)" \
    "$(field .rate_limits.seven_day.resets_at)" '%a %H:%M'
  # Only sent behind a Claude apps gateway that sets a spend limit.
  used="$(field .rate_limits.spend_limit.used_usd)"
  limit="$(field .rate_limits.spend_limit.limit_usd)"
  label=spend
  if [[ -n "$used" && -n "$limit" ]]; then
    label="$(LC_ALL=C printf '$%.0f/$%.0f' "$used" "$limit" 2>/dev/null || echo spend)"
  fi
  usage "$label" "$(field .rate_limits.spend_limit.used_percentage)" \
    "$(field .rate_limits.spend_limit.resets_at)" '%b %d'
}

first_line
second="$(second_line)"
if [[ -n "$second" ]]; then
  printf '\n%s' "${second# }"
fi
exit 0
