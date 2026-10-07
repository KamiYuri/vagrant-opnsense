#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' 0
export GIT_AUTHOR_NAME=Tester GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=Tester GIT_COMMITTER_EMAIL=test@example.invalid
mkdir -p "$TMP/bin" "$TMP/project/vagrant" "$TMP/project/bin" "$TMP/guest"
cp "$ROOT/bin/opsenv" "$TMP/project/bin/opsenv"
cp "$ROOT/vagrant/common.rb" "$TMP/project/vagrant/common.rb"
: > "$TMP/project/Vagrantfile"
: > "$TMP/FreeBSD-15.1.box"
git init -q -b stable/26.7 "$TMP/upstream"
mkdir -p "$TMP/upstream/src/opnsense/scripts" "$TMP/upstream/Mk"
printf 'TREES=bin etc\n' > "$TMP/upstream/Makefile"
printf 'CORE_ABIS?=26.7\n' > "$TMP/upstream/Mk/version.mk"
printf 'local-original\n' > "$TMP/upstream/local"
printf '#!/bin/sh\n' > "$TMP/upstream/src/opnsense/scripts/example"
printf '#!/bin/sh\n' > "$TMP/upstream/src/opnsense/scripts/café"
printf 'remove me\n' > "$TMP/upstream/old"
chmod +x "$TMP/upstream/src/opnsense/scripts/example"
git -C "$TMP/upstream" add .
git -C "$TMP/upstream" commit -qm initial

git clone -q "$TMP/upstream" "$TMP/core"
printf 'local-edit\n' > "$TMP/core/local"
rm "$TMP/core/old"
printf 'my untracked file\n' > "$TMP/core/untracked notes"
printf 'upstream update\n' > "$TMP/upstream/new"
git -C "$TMP/upstream" add .
git -C "$TMP/upstream" commit -qm upstream
printf 'not_created\n' > "$TMP/state"

cat > "$TMP/bin/vagrant" <<'MOCK'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$MOCK_LOG"
case "$*" in
    'plugin list') [ ! -f "$MOCK_GUEST/plugin" ] || printf 'vagrant-libvirt (0.12.2, global)\n' ;;
    'plugin install '*) : > "$MOCK_GUEST/plugin" ;;
    'box list') [ ! -f "$MOCK_GUEST/box" ] || printf 'Much-longer-box-name (libvirt, 0)\nBKCS/FreeBSD-15.1-ZFS   (libvirt, 0)\n' ;;
    'box add '*) : > "$MOCK_GUEST/box" ;;
    'status --machine-readable') printf '0,default,state,%s\n' "$(cat "$MOCK_STATE")" ;;
    'up') printf 'poweroff\n' > "$MOCK_STATE" ;;
    'up --no-provision') printf 'running\n' > "$MOCK_STATE" ;;
    'reload --no-provision') printf 'running\n' > "$MOCK_STATE" ;;
    'ssh -c opnsense-version -a') printf '26.7\n' ;;
    *'pkg update'*'opnsense-update -c'*) [ ! -f "$MOCK_GUEST/current" ] ;;
    'ssh -c sudo opnsense-update -bkp') : > "$MOCK_GUEST/current" ;;
    'snapshot list') [ ! -f "$MOCK_GUEST/snapshot" ] || printf '==> default:   opsenv-previous\n' ;;
    'snapshot delete opsenv-previous') rm "$MOCK_GUEST/snapshot" ;;
    'snapshot save opsenv-previous') : > "$MOCK_GUEST/snapshot" ;;
    'upload '*'/home/vagrant/opsenv-core.tar.gz') cp "$2" "$MOCK_GUEST/opsenv-core.tar.gz" ;;
    'upload '*'/home/vagrant/opsenv-modes.txt') cp "$2" "$MOCK_GUEST/opsenv-modes.txt" ;;
    *'tar -xzf /home/vagrant/opsenv-core.tar.gz'*)
        tar -tzf "$MOCK_GUEST/opsenv-core.tar.gz" | grep -q '^Makefile$'
        ! tar -tzf "$MOCK_GUEST/opsenv-core.tar.gz" | grep -q '^.git/'
        mkdir -p "$MOCK_GUEST/core"
        tar -xzf "$MOCK_GUEST/opsenv-core.tar.gz" -C "$MOCK_GUEST/core"
        ;;
    'ssh -c sudo sh -c "cd /var/vagrant/core && make install"') [ -f "$MOCK_GUEST/core/Makefile" ] ;;
    *'mount | grep -q " on /usr/local '* ) ;;
    *) printf 'Unexpected Vagrant command: %s\n' "$*" >&2; exit 2 ;;
esac
MOCK
chmod +x "$TMP/bin/vagrant"
export PATH="$TMP/bin:$PATH" MOCK_GUEST="$TMP/guest" MOCK_STATE="$TMP/state" MOCK_LOG="$TMP/log"
export PROVIDER=libvirt OPSENV_CORE_REMOTE="$TMP/upstream" OPSENV_BOX_FILE="$TMP/FreeBSD-15.1.box" SYNC_TYPE=none
sh "$TMP/project/bin/opsenv" > "$TMP/first.log" 2>&1 || { sed -n '1,200p' "$TMP/first.log"; exit 1; }
[ "$(cat "$TMP/state")" = running ]
[ -f "$TMP/guest/snapshot" ]
[ "$(cat "$TMP/core/local")" = local-edit ]
[ "$(cat "$TMP/guest/core/local")" = local-edit ]
[ -f "$TMP/guest/core/untracked notes" ]
[ -f "$TMP/guest/core/src/opnsense/scripts/café" ]
[ ! -e "$TMP/guest/core/old" ]
grep -q '^snapshot save opsenv-previous$' "$TMP/log"
grep -q '^ssh -c sudo opnsense-update -bkp$' "$TMP/log"
grep -q '^reload --no-provision$' "$TMP/log"

printf 'shutoff\n' > "$TMP/state"
sh "$TMP/project/bin/opsenv" > "$TMP/second.log" 2>&1 || { sed -n '1,200p' "$TMP/second.log"; exit 1; }
grep -q '^up --no-provision$' "$TMP/log"
[ "$(grep -c '^snapshot save opsenv-previous$' "$TMP/log")" -eq 1 ]
grep -q 'Guest packages, base and kernel already current' "$TMP/second.log"
rm "$TMP/guest/current"
sh "$TMP/project/bin/opsenv" > "$TMP/third.log" 2>&1 || { sed -n '1,200p' "$TMP/third.log"; exit 1; }
[ "$(grep -c '^snapshot save opsenv-previous$' "$TMP/log")" -eq 2 ]
[ "$(grep -c '^snapshot delete opsenv-previous$' "$TMP/log")" -eq 1 ]
[ -f "$TMP/guest/snapshot" ]
printf 'Full temporary workflow passed (clone, update, bootstrap, snapshot rotation, firmware, upload, install, rerun)\n'
