#!/bin/bash
# Evidence driver: one real bin/fm-spawn.sh worker launch in a disposable lab
# home, following bin/fm-live-lab.sh's own worker recipe (lab home, private tmux
# server, lab-private treehouse root, lab-private project and origin, scaffolded
# brief, backlog item, then the spawn), with the firstmate tree checked out at
# <ref>. Claude's config dir is pointed inside the lab so the operator's
# ~/.claude.json is never written; the worker CLI therefore starts without a
# login, which the spawn itself does not depend on.
#
# Usage: drive-worker-launch.sh <source-checkout> <ref> <label>
set -u
SRC=$1
REF=$2
LABEL=$3

ROOT=$(mktemp -d /tmp/fmlab.XXXXXX) || exit 1
ROOT=$(cd -P "$ROOT" && pwd -P)
LAB="$ROOT/home"
CLAUDE_DIR="$ROOT/claude-config"
ID="lab$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')-worker"
TMUX_DIR=
mkdir -p "$CLAUDE_DIR" "$ROOT/treehouse"

# The operator's store is rewritten by every live Claude session, so its bytes
# prove nothing; what matters is that no project entry under this lab lands in it.
lab_entries_in_operator_store() {
  [ -f "$HOME/.claude.json" ] || { echo 0; return; }
  jq -r --arg root "$ROOT" '[.projects // {} | keys[] | select(startswith($root) or startswith("/private" + $root))] | length' "$HOME/.claude.json"
}
ls -1A "$HOME/.treehouse" 2>/dev/null | sort > "$ROOT/.treehouse-before"

lab_run() {
  env -i "HOME=$HOME" "USER=${USER:-$(id -un)}" "LOGNAME=${USER:-$(id -un)}" "PATH=$PATH" \
    "SHELL=${SHELL:-/bin/zsh}" "TERM=xterm-256color" "LANG=${LANG:-en_US.UTF-8}" \
    "TMUX_TMPDIR=$TMUX_DIR" "TREEHOUSE_ROOT=$ROOT/treehouse" "FM_BACKEND=tmux" \
    "DISABLE_AUTOUPDATER=1" "CLAUDE_CONFIG_DIR=$CLAUDE_DIR" "$@"
}
lab_tmux() { env -u TMUX TMUX_TMPDIR="$TMUX_DIR" tmux "$@"; }
scrub() { sed -e "s#$ROOT#<lab>#g" -e "s#$ID#<worker-id>#g"; }

teardown() {
  local home_hash dir added
  [ -z "$TMUX_DIR" ] || lab_tmux kill-server 2>/dev/null
  sleep 2
  [ ! -f "$LAB/.fm-lab-home" ] || "$SRC/bin/fm-lab-home.sh" teardown "$LAB" >/dev/null 2>&1
  home_hash=$(printf '%s' "$LAB" | shasum -a 256 | awk '{print $1}')
  for dir in "/tmp/fm-$ID+$home_hash" "/tmp/fm-$ID"; do
    if [ -d "$dir" ] && [ ! -L "$dir" ] && [ -O "$dir" ]; then rm -rf "$dir"; fi
  done
  echo
  echo "## teardown"
  echo "lab project entries written to the operator's ~/.claude.json: $(lab_entries_in_operator_store)"
  echo "lab project entries written to the lab's own Claude store: $(jq -r '.projects // {} | length' "$CLAUDE_DIR/.claude.json" 2>/dev/null || echo 0)"
  added=$(ls -1A "$HOME/.treehouse" 2>/dev/null | sort | comm -13 "$ROOT/.treehouse-before" - | tr '\n' ' ')
  echo "operator ~/.treehouse gained entries: ${added:-none}"
  chmod -R u+w "$ROOT" 2>/dev/null
  rm -rf "$ROOT"
  echo "lab removed: $([ -e "$ROOT" ] && echo NO || echo yes)"
}
trap teardown EXIT

echo "# worker launch, firstmate tree at $LABEL ($REF)"
echo "host bash: $(command -v bash) - $(bash --version | head -1)"

"$SRC/bin/fm-lab-home.sh" create "$LAB" >/dev/null || { echo "cannot create the lab home"; exit 1; }
git -C "$LAB" init -q -b main || exit 1
git -C "$LAB" fetch -q "$SRC" "$REF" || { echo "cannot fetch $REF"; exit 1; }
git -C "$LAB" checkout -q -f -B main FETCH_HEAD || exit 1
git -C "$LAB" config user.name lab && git -C "$LAB" config user.email lab@example.invalid
mkdir -p "$LAB/state" "$LAB/data" "$LAB/config" "$LAB/projects"
printf 'tmux\n' > "$LAB/config/backend"
printf 'claude\n' > "$LAB/config/crew-harness"
printf 'auto\n' > "$LAB/config/claude-permission-mode"
echo "lab tree: $(git -C "$LAB" rev-parse HEAD)"

TMUX_DIR=$("$LAB/bin/fm-lab-home.sh" tmux-dir "$LAB") || { echo "cannot create the private tmux directory"; exit 1; }
lab_run tmux -f /dev/null new-session -d -s firstmate -n lab -x 220 -y 60 -c "$ROOT" || { echo "cannot start the lab tmux server"; exit 1; }

# The lab project, exactly as bin/fm-live-lab.sh's make_notes_project builds it.
seed="$ROOT/origins/notes-seed"
origin="$ROOT/origins/notes.git"
mkdir -p "$seed/notes"
git init -q -b main "$seed"
printf 'NOTES = []\n' > "$seed/notes/__init__.py"
printf '# notes\n\nA tiny notes library for lab work.\n' > "$seed/README.md"
git -C "$seed" add -A
git -C "$seed" -c user.name=lab -c user.email=lab@example.invalid commit -q -m "seed notes"
git clone -q --bare "$seed" "$origin"
git clone -q "$origin" "$LAB/projects/notes"
printf '# Projects\n\n- notes [local-only +yolo] - tiny lab notes library\n' > "$LAB/data/projects.md"

(cd "$LAB" && lab_run FM_HOME="$LAB" "$LAB/bin/fm-brief.sh" "$ID" notes --mode local-only) >/dev/null || { echo "cannot scaffold the brief"; exit 1; }
TASK_TEXT="Lab worker for a launch check. Do nothing until the gate file $LAB/data/$ID/gate exists and you receive a message to resume." \
SPEC_TEXT="Right after setup, append one paused status line naming the gate file $LAB/data/$ID/gate and end your turn. Nothing else is in scope." \
  python3 - "$LAB/data/$ID/brief.md" <<'PY' || exit 1
import os, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
text = text.replace("{TASK}", os.environ["TASK_TEXT"], 1).replace("{FIRSTMATE_SPEC}", os.environ["SPEC_TEXT"], 1)
open(path, "w", encoding="utf-8").write(text)
PY
(cd "$LAB" && lab_run FM_HOME="$LAB" "$LAB/bin/fm-tasks-axi.sh" add "$ID" "lab launch check" --kind ship --repo notes) >/dev/null || { echo "cannot add the backlog item"; exit 1; }

echo
echo "## backlog item before the launch"
(cd "$LAB" && lab_run FM_HOME="$LAB" "$LAB/bin/fm-tasks-axi.sh" show "$ID") 2>&1 | scrub

echo
echo "## the launch"
echo "\$ FM_HOME=<lab>/home bin/fm-spawn.sh <worker-id> <lab>/home/projects/notes --mode local-only --yolo on --harness claude --model sonnet --effort low"
(cd "$LAB" && lab_run FM_HOME="$LAB" "$LAB/bin/fm-spawn.sh" "$ID" "$LAB/projects/notes" \
  --mode local-only --yolo on --harness claude --model sonnet --effort low) > "$ROOT/spawn.out" 2>&1
rc=$?
scrub < "$ROOT/spawn.out"
echo "fm-spawn.sh exit status: $rc"

echo
echo "## state after the launch"
if [ -f "$LAB/state/$ID.meta" ]; then
  echo "task record state/<worker-id>.meta: present"
  grep -E '^(kind|harness|mode|window|worktree)=' "$LAB/state/$ID.meta" | scrub
else
  echo "task record state/<worker-id>.meta: absent"
fi
echo "backlog item:"
(cd "$LAB" && lab_run FM_HOME="$LAB" "$LAB/bin/fm-tasks-axi.sh" show "$ID") 2>&1 | scrub
echo "lab tmux windows:"
lab_tmux list-windows -t firstmate -F '#{window_name} dead=#{pane_dead} cmd=#{pane_current_command}' 2>&1 | scrub
sleep 12
win=$(lab_tmux list-windows -t firstmate -F '#{window_name} #{window_id}' | awk -v n="$ID" 'index($1, n) { print $2; exit }')
if [ -n "$win" ]; then
  echo "worker pane (last non-empty lines):"
  lab_tmux capture-pane -p -t "$win" 2>&1 | grep -v '^[[:space:]]*$' | tail -n 25 | scrub
fi
exit "$rc"
