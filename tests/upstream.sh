#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
RELEASE=$(sed -n "s/.*OPNSENSE_RELEASE', *'\([^']*\)'.*/\1/p" "$ROOT/vagrant/common.rb")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' 0
curl -fsSL "https://raw.githubusercontent.com/opnsense/core/stable/$RELEASE/src/etc/config.xml.sample" -o "$TMP/config.xml"
curl -fsSL 'https://raw.githubusercontent.com/opnsense/update/master/src/bootstrap/opnsense-bootstrap.sh.in' -o "$TMP/upstream.sh"

for pattern in 'mismatch0' 'mismatch1' '<ipaddrv6>dhcp6</ipaddrv6>' \
    '<ipaddrv6>idassoc6</ipaddrv6>' '<track6-interface>wan</track6-interface>' \
    '<track6-prefix-id>0</track6-prefix-id>' '192.168.1.1<' '192.168.1.' \
    '<group>admins</group>' '<filter>' '<blockpriv>1</blockpriv>' '</member>' '</user>';
do
    if ! grep -Fq "$pattern" "$TMP/config.xml"; then
        printf '::warning::Core config.xml.sample no longer contains %s\n' "$pattern" >&2
        exit 1
    fi
done
if ! grep -Eq '^[[:space:]]*reboot$' "$TMP/upstream.sh" ||
   ! grep -Fq 'pkg unlock' "$TMP/upstream.sh"; then
    printf '::warning::Upstream bootstrap patch targets have changed\n' >&2
    exit 1
fi
if ! grep -Fq '<ipaddrv6>idassoc6' "$ROOT/bootstrap.sh"; then
    printf '::warning::Local bootstrap no longer removes the LAN IPv6 default\n' >&2
    exit 1
fi
sh -n "$ROOT/bootstrap.sh" "$ROOT/bin/opsenv"
printf 'Upstream bootstrap and config anchors match %s\n' "$RELEASE"
