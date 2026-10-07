#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' 0
export GIT_AUTHOR_NAME=Tester GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=Tester GIT_COMMITTER_EMAIL=test@example.invalid
mkdir -p "$TMP/bin" "$TMP/project/vagrant" "$TMP/remote" "$TMP/project/bin"
cp "$ROOT/bin/opsenv" "$TMP/project/bin/opsenv"
: > "$TMP/project/Vagrantfile"
cp "$ROOT/vagrant/common.rb" "$TMP/project/vagrant/common.rb"
git init -q -b stable/26.7 "$TMP/remote"
printf 'initial\n' > "$TMP/remote/code"
printf 'local-original\n' > "$TMP/remote/local"
git -C "$TMP/remote" add .
git -C "$TMP/remote" commit -qm initial
git clone -q "$TMP/remote" "$TMP/core"

cat > "$TMP/bin/vagrant" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> "$MOCK_LOG"
case "$*" in
    'plugin list') printf 'vagrant-libvirt (0.12.2, global)\n' ;;
    'box list') printf 'BKCS/FreeBSD-15.1-ZFS (libvirt, 0)\n' ;;
    'status --machine-readable') printf '0,default,state,running\n' ;;
    'ssh -c opnsense-version -a') printf '26.7\n' ;;
    *'pkg update'*'opnsense-update -c'*) exit "${MOCK_UPDATES:-1}" ;;
    'snapshot list') printf 'No snapshots have been taken yet.\n' ;;
    'snapshot save opsenv-previous'|'reload --no-provision') ;;
    'ssh -c test -f /var/vagrant/core/Makefile') ;;
    *'mkdir -p /var/vagrant/core/work'*) ;;
    *'mount | grep -q " on /usr/local '* ) ;;
    'ssh -c sudo sh -c "cd /var/vagrant/core && make install"') ;;
    'ssh -c sudo opnsense-update -bkp') ;;
    *) printf 'Unexpected Vagrant command: %s\n' "$*" >&2; exit 2 ;;
esac
MOCK
chmod +x "$TMP/bin/vagrant"
export PATH="$TMP/bin:$PATH" PROVIDER=libvirt OPSENV_CORE_REMOTE="$TMP/remote" MOCK_LOG="$TMP/log"

printf 'local-edit\n' > "$TMP/core/local"
printf 'upstream\n' > "$TMP/remote/code"
git -C "$TMP/remote" add .
git -C "$TMP/remote" commit -qm upstream
sh "$TMP/project/bin/opsenv" > "$TMP/success.log" 2>&1 || { sed -n '1,200p' "$TMP/success.log"; exit 1; }
[ "$(git -C "$TMP/core" show HEAD:code)" = upstream ]
[ "$(cat "$TMP/core/local")" = local-edit ]
grep -q 'sudo sh -c "cd /var/vagrant/core && make install"' "$TMP/log"

MOCK_UPDATES=0 sh "$TMP/project/bin/opsenv" > "$TMP/firmware.log" 2>&1 || { sed -n '1,200p' "$TMP/firmware.log"; exit 1; }
grep -q 'snapshot save opsenv-previous' "$TMP/log"
grep -q 'sudo opnsense-update -bkp' "$TMP/log"
grep -q 'reload --no-provision' "$TMP/log"

printf 'my-change\n' > "$TMP/core/code"
printf 'their-change\n' > "$TMP/remote/code"
git -C "$TMP/remote" add .
git -C "$TMP/remote" commit -qm conflict
if sh "$TMP/project/bin/opsenv" > "$TMP/conflict.log" 2>&1; then
    printf 'Expected a conflict but update succeeded\n' >&2
    exit 1
fi
grep -q 'Unresolved files:' "$TMP/conflict.log"
git -C "$TMP/core" rev-parse --verify refs/opsenv/last-stash >/dev/null
[ "$(git -C "$TMP/core" show HEAD:code)" = their-change ]
mv "$TMP/core" "$TMP/conflicted-core"
git clone -q "$TMP/remote" "$TMP/core"
printf 'local-commit\n' > "$TMP/core/code"
git -C "$TMP/core" add code
git -C "$TMP/core" commit -qm 'local commit'
printf 'upstream-again\n' > "$TMP/remote/code"
git -C "$TMP/remote" add code
git -C "$TMP/remote" commit -qm 'upstream again'
printf 'unsaved-edit\n' > "$TMP/core/local"
if sh "$TMP/project/bin/opsenv" > "$TMP/merge-conflict.log" 2>&1; then
    printf 'Expected a merge conflict but update succeeded\n' >&2
    exit 1
fi
git -C "$TMP/core" rev-parse --verify refs/opsenv/pending-stash >/dev/null
printf 'resolved\n' > "$TMP/core/code"
git -C "$TMP/core" add code
git -C "$TMP/core" commit -qm 'resolve merge'
sh "$TMP/project/bin/opsenv" > "$TMP/recovered.log" 2>&1 || { sed -n '1,200p' "$TMP/recovered.log"; exit 1; }
[ "$(cat "$TMP/core/local")" = unsaved-edit ]
if git -C "$TMP/core" rev-parse -q --verify refs/opsenv/pending-stash >/dev/null; then
    printf 'Pending stash was not cleared after recovery\n' >&2
    exit 1
fi
printf 'Updater tests passed\n'
