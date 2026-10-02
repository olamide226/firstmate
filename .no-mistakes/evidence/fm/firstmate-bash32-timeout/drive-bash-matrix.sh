#!/bin/bash
# Evidence driver: run tests/fm-timeout-lib.test.sh and one direct bounded call
# with a scratch-built Bash first on PATH. Usage: drive-bash-matrix.sh <scratch> <repo>
S=$1
REPO=$2
cd "$REPO" || exit 1
for v in 4.4.18 5.2.37; do
  B="$S/inst-$v/bin"
  echo "=================== Bash $v ==================="
  PATH="$B:$PATH" bash -c 'echo "bash on PATH: $BASH_VERSION, BASHPID is ${BASHPID:+set}${BASHPID:-unset}"'
  echo "\$ unset BASHPID   # what the BASHPID-free test cases attempt"
  PATH="$B:$PATH" bash -c 'unset BASHPID; echo "rc=$? BASHPID afterwards: ${BASHPID:+still set}${BASHPID:-gone}"' 2>&1
  echo "\$ bash -c 'set -eu; . bin/fm-timeout-lib.sh; ( fm_exec_timed 5 1 bash -c \"echo ran; exit 7\" )'"
  PATH="$B:$PATH" bash -c 'set -eu; . bin/fm-timeout-lib.sh; rc=0; ( fm_exec_timed 5 1 bash -c "echo ran; exit 7" ) || rc=$?; echo "rc=$rc"' 2>&1
  echo "\$ bash tests/fm-timeout-lib.test.sh"
  PATH="$B:$PATH" bash tests/fm-timeout-lib.test.sh > "$S/out-$v.txt" 2> "$S/err-$v.txt"
  echo "exit=$?"
  cat "$S/out-$v.txt"
  echo "--- stderr of the test run ---"
  if [ -s "$S/err-$v.txt" ]; then cat "$S/err-$v.txt"; else echo "(empty)"; fi
  echo
done
