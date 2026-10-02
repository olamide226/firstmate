#!/bin/bash
# Evidence driver: exercises bin/fm-timeout-lib.sh's fm_exec_timed owner
# resolution on the host Bash. Usage: drive-owner-resolution.sh <lib> <scratch>
LIB=$1
T=$2
P="$T/perl-only"
mkdir -p "$P"
ln -sf "$(command -v perl)" "$P/perl"
ln -sf /bin/bash "$P/bash"
ln -sf /bin/sleep "$P/sleep"

alive() { if kill -0 "$1" 2>/dev/null; then echo alive; else echo gone; fi; }
now() { perl -MTime::HiRes=time -e 'printf "%.2f", time'; }
since() { perl -MTime::HiRes=time -e 'printf "%.2f", time - $ARGV[0]' "$1"; }
wait_file() { local i=0; while [ ! -s "$1" ] && [ "$i" -lt 200 ]; do i=$((i + 1)); sleep 0.05; done; }
wait_gone() { local i=0; while kill -0 "$1" 2>/dev/null && [ "$i" -lt 400 ]; do i=$((i + 1)); sleep 0.05; done; }

echo "host: $(bash --version | head -1)"
echo
echo "## A. PATH holds no sh at all (perl, bash, sleep only), set -eu: the frame is still resolved"
echo "PATH entries: $(ls "$P" | tr '\n' ' ')"
bash -c 'set -eu; . "$1"; rc=0; ( PATH=$2 fm_exec_timed 5 1 bash -c "echo ran-without-sh-on-PATH; exit 3" ) || rc=$?; echo "rc=$rc"' _ "$LIB" "$P" 2>&1

echo
echo "## B. subshell call: the calling script is the owner."
echo "##    The script is SIGKILLed mid-run; the command must end long before its 60s bound."
d="$T/B"
mkdir -p "$d"
bash -c 'set -eu; . "$1"; echo $$ > "$2/script"; ( fm_exec_timed 60 1 bash -c "echo \$\$ > \"\$1/cmd\"; exec sleep 300" _ "$2" ) & echo $! > "$2/watchdog"; wait' _ "$LIB" "$d" >/dev/null 2>&1 &
wait_file "$d/cmd"
script=$(cat "$d/script"); wd=$(cat "$d/watchdog"); cmd=$(cat "$d/cmd")
echo "before: script=$(alive "$script") watchdog=$(alive "$wd") command=$(alive "$cmd")"
s=$(now)
kill -KILL "$script"
wait_gone "$cmd"
echo "after SIGKILL of script: watchdog=$(alive "$wd") command=$(alive "$cmd") (ended $(since "$s")s after the kill; bound was 60s)"
kill -KILL "$cmd" "$wd" 2>/dev/null

echo
echo "## C. unsubshelled call: the script's PARENT is the owner."
echo "##    The parent is SIGKILLed; the command must end long before its 60s bound."
d="$T/C"
mkdir -p "$d"
bash -c 'echo $$ > "$2/parent"; bash -c '\''set -eu; . "$1"; echo $$ > "$2/watchdog"; fm_exec_timed 60 1 bash -c "echo \$\$ > \"\$1/cmd\"; exec sleep 300" _ "$2"'\'' _ "$@"; :' _ "$LIB" "$d" >/dev/null 2>&1 &
wait_file "$d/cmd"
parent=$(cat "$d/parent"); wd=$(cat "$d/watchdog"); cmd=$(cat "$d/cmd")
echo "before: parent=$(alive "$parent") watchdog=$(alive "$wd") command=$(alive "$cmd")"
s=$(now)
kill -KILL "$parent"
wait_gone "$cmd"
echo "after SIGKILL of parent: watchdog=$(alive "$wd") command=$(alive "$cmd") (ended $(since "$s")s after the kill; bound was 60s)"
kill -KILL "$cmd" "$wd" 2>/dev/null

echo
echo "## D. no false positive: with its owner alive a 3s command runs to completion (subshell, then unsubshelled)"
bash -c 'set -eu; . "$1"; s=$SECONDS; rc=0; ( fm_exec_timed 20 1 bash -c "sleep 3; echo finished-subshell" ) || rc=$?; echo "rc=$rc elapsed=$((SECONDS-s))s"' _ "$LIB" 2>&1
bash -c 's=$SECONDS; rc=0; bash -c '\''set -eu; . "$1"; fm_exec_timed 20 1 bash -c "sleep 3; echo finished-unsubshelled"'\'' _ "$1" || rc=$?; echo "rc=$rc elapsed=$((SECONDS-s))s"' _ "$LIB" 2>&1

echo
echo "## E. the pid the fallback computes is the real subshell pid (\$! of that subshell), not the script pid"
bash -c 'set -u; ( f=${BASHPID:-$(exec /bin/sh -c '\''printf "%s\n" "$PPID"'\'')}; echo "$f" > "$1/frame" ) & sub=$!; wait; echo "script=$$ subshell=$sub fallback-frame=$(cat "$1/frame") BASHPID=${BASHPID-<unset>}"' _ "$T" 2>&1
