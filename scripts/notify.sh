#!/bin/bash
# Foreman Notification hook: show the event message as a macOS banner.
# Idle-prompt events fire ~60s after every turn the manager has not replied to,
# so they are dropped; only permission prompts and foreman's own pushes banner.
# The notifications option (default on) turns the whole hook off; nothing else reads it.
[ "${CLAUDE_PLUGIN_OPTION_NOTIFICATIONS:-true}" = false ] && exit 0
out=$(/usr/bin/python3 -c '
import json, os, re, sys
try:
    d = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)
m = (d.get("message") or "").replace("\n", " ")
if d.get("notification_type") == "idle_prompt" or "waiting for your input" in m:
    raise SystemExit(3)
# On iTerm2 both fields are written into a terminal escape sequence, where a BEL ends it
# and an ESC or a C1 control starts the next one. Control characters go; the text stays.
ctl = re.compile(r"[\x00-\x1f\x7f-\x9f]")
print(ctl.sub("", m))
print(ctl.sub("", os.path.basename(d.get("cwd") or "")))
' 2>/dev/null) || exit 0
{ IFS= read -r msg; IFS= read -r dir; } <<<"$out"
[ -z "$msg" ] && msg="Claude Code needs you"
title="Claude Code"
[ -n "$dir" ] && title="Claude Code — $dir"

if [ -n "${FOREMAN_NOTIFY_DRY_RUN:-}" ]; then
  echo "$title"
  echo "$msg"
  exit 0
fi

# iTerm2 and Ghostty attribute an OSC 9 notification to the session that wrote it, so
# clicking the banner switches to that tab or split; an osascript banner belongs to Script
# Editor. The hook has no terminal of its own, but Claude Code names the session process in
# CLAUDE_PID and that one does. Over ssh iTerm2 forwards only LC_TERMINAL (Ghostty forwards
# TERM_PROGRAM); inside tmux or screen the pty belongs to the multiplexer, which drops the
# sequence, so those get the plain banner.
# FOREMAN_NOTIFY_TTY is the test seam: deliver there and never fall through to a real banner.
iterm=""
case "${TERM_PROGRAM:-}:${LC_TERMINAL:-}" in iTerm.app:*|:iTerm2|ghostty:*) [ -z "${TMUX:-}${STY:-}" ] && iterm=1 ;; esac
tty=""
if [ -n "$iterm" ]; then
  tty=${FOREMAN_NOTIFY_TTY:-}
  if [ -z "$tty" ] && [ -n "${CLAUDE_PID:-}" ]; then
    t=$(ps -o tty= -p "$CLAUDE_PID" 2>/dev/null | tr -d ' ')
    case "$t" in ''|'?'|'??') ;; *) tty="/dev/$t" ;; esac
  fi
fi
if [ -n "$tty" ] && [ -w "$tty" ]; then
  printf '\033]9;%s: %s\007' "$title" "$msg" > "$tty"
  exit 0
fi
[ -n "${FOREMAN_NOTIFY_TTY:-}" ] && exit 0

[ -x /usr/bin/osascript ] || exit 0
/usr/bin/osascript -e 'on run argv' \
  -e 'display notification (item 1 of argv) with title (item 2 of argv) sound name "Glass"' \
  -e 'end run' -- "$msg" "$title" >/dev/null 2>&1
exit 0
