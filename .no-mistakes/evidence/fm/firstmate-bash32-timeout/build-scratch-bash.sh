#!/bin/bash
# Evidence helper: build a GNU Bash release from its ftp.gnu.org tarball inside
# a scratch directory, so the timeout tests can run on Bash versions this host
# does not have (it ships only 3.2.57). Nothing is installed outside <scratch>.
# Usage: build-scratch-bash.sh <scratch> <version> [configure-arg...]
set -u
S=$1
v=$2
shift 2
cd "$S" || exit 1
tar -xzf "bash-$v.tar.gz" || exit 1
cd "bash-$v" || exit 1
./configure --without-bash-malloc --disable-nls "$@" > configure.log 2>&1 || { echo "configure $v failed"; tail -n 5 configure.log; exit 1; }
make -j8 > make.log 2>&1 || { echo "make $v failed"; tail -n 8 make.log; exit 1; }
mkdir -p "$S/inst-$v/bin"
cp bash "$S/inst-$v/bin/bash"
"$S/inst-$v/bin/bash" --version | head -n 1
