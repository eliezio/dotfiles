# Shared logging utilities. Source from apply.sh, or include from chezmoi
# scripts via `{{ include "scripts/lib/log.sh" }}`.
#
# Provides:
#   log_step / log_success / log_error / log_info — colored one-liners.
#
# Each line is prefixed with [N] (top level) or [N.M] (chezmoi-managed scripts
# launched from apply.sh) plus wall-clock and elapsed-since-start timestamps.
#
# Requires bash 5+ or zsh (for $EPOCHREALTIME). Caller must self-exec into
# bash 5+ on macOS.

# zsh needs the datetime module for $EPOCHREALTIME and strftime; bash 5+ has
# both natively.
[[ -n ${ZSH_VERSION:-} ]] && zmodload zsh/datetime 2>/dev/null

# Set start epoch once per invocation chain. Exported so children compute the
# same elapsed clock.
: "${LOG_START_EPOCH:=$EPOCHREALTIME}"
export LOG_START_EPOCH

# Local step counter; reset to 0 in each new shell.
LOG_STEP_NUM=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

_log_prefix() {
  # Normalize EPOCHREALTIME's fractional to exactly 3 digits (milliseconds);
  # avoids int64 overflow when bash/zsh report >6 fractional digits.
  local now="$EPOCHREALTIME"
  local now_s="${now%.*}" now_ms="${now#*.}"
  now_ms="${now_ms}000"; now_ms="${now_ms:0:3}"

  local start_s="${LOG_START_EPOCH%.*}" start_ms="${LOG_START_EPOCH#*.}"
  start_ms="${start_ms}000"; start_ms="${start_ms:0:3}"

  local hms
  if [[ -n ${ZSH_VERSION:-} ]]; then
    hms=$(strftime '%H:%M:%S' "$now_s")
  else
    printf -v hms '%(%H:%M:%S)T' "$now_s"
  fi

  # 10# forces base-10 so leading zeros aren't read as octal.
  local diff_ms=$(( (now_s - start_s) * 1000 + 10#$now_ms - 10#$start_ms ))
  local elapsed_ds=$(( diff_ms / 100 ))
  local step="${LOG_STEP_PREFIX:+$LOG_STEP_PREFIX.}$LOG_STEP_NUM"
  printf '[%s] %s.%s +%d.%ds' "$step" "$hms" "$now_ms" $((elapsed_ds / 10)) $((elapsed_ds % 10))
}

log_step()    { LOG_STEP_NUM=$((LOG_STEP_NUM + 1)); echo -e "${BLUE}▶ STEP${NC} $(_log_prefix) - $1" >&2; }
log_success() { echo -e "${GREEN}✔ DONE${NC} $(_log_prefix) - $1" >&2; }
log_error()   { echo -e "${RED}✘ FAIL${NC} $(_log_prefix) - $1" >&2; }
log_info()    { echo -e "${YELLOW}ⓘ INFO${NC} $(_log_prefix) - $1" >&2; }
