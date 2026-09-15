#!/bin/sh

set -e

# All configuration is supplied by the Vagrantfile via environment variables.
# Fail fast if invoked standalone without those vars set.
: "${BOOTSTRAP_SCRIPT_URL:?BOOTSTRAP_SCRIPT_URL must be set (run via Vagrant or export it manually)}"
: "${OPNSENSE_RELEASE:?OPNSENSE_RELEASE must be set}"
: "${VIRTUAL_MACHINE_IP:?VIRTUAL_MACHINE_IP must be set}"

# Tiền tố tên card mạng trong guest. Vagrantfile truyền vào theo provider;
# libvirt và VirtualBox đều dùng virtio nên giá trị là vtnet. Biến trống thì dò
# trực tiếp từ hệ thống, lấy card vật lý đầu tiên mà ifconfig liệt kê.
NIC_PREFIX="${NIC_PREFIX:-}"
if [ -z "${NIC_PREFIX}" ]; then
    NIC_PREFIX=$(ifconfig -l | tr ' ' '\n' \
        | grep -E '^(vtnet|vmx|em|igb|re)[0-9]+$' \
        | head -1 | sed -e 's/[0-9]*$//')
fi
: "${NIC_PREFIX:?Không xác định được tên card mạng trong guest}"
echo "==> NIC_PREFIX = ${NIC_PREFIX}"

# Các mảnh XML được nối thẳng vào config.xml, nên một ký tự CR lọt vào là giá
# trị cấu hình sai. Chuẩn hoá tại chỗ, phòng trường hợp chúng rời host Windows
# với kết thúc dòng CRLF.
for f in files/*.xml; do
    [ -f "$f" ] || continue
    tr -d '\r' < "$f" > "$f.lf" && mv "$f.lf" "$f"
done

# Download the OPNsense bootstrap script from the update repo
fetch -o opnsense-bootstrap.sh "${BOOTSTRAP_SCRIPT_URL}"

# Remove reboot command from bootstrap script
sed -i '' -e '/reboot$/d' opnsense-bootstrap.sh

# Remove pkg unlock command from bootstrap script, which causes an error due to
# an upstream bug. https://github.com/freebsd/pkg/issues/2278
# This won't hurt even with the bug eventually fixed, because we don't have any
# locked packages.
sed -i '' -e '/pkg unlock/d' opnsense-bootstrap.sh

# Start bootstrap. The upstream script already defaults to account `opnsense`
# and repository `core`, and derives the branch from the release on its own
# (-r 26.7 -> stable/26.7), so the release is the only input it needs.
#   -r <release>  = target OPNsense release
#   -y            = assume yes, run unattended
sh ./opnsense-bootstrap.sh -r "${OPNSENSE_RELEASE}" -y

# Bail out early if the bootstrap above didn't actually install OPNsense.
# Without this, the rest of the script silently runs sed against a missing
# config.xml and the VM halts in a half-provisioned state.
if [ ! -f /usr/local/etc/config.xml ]; then
    echo "FATAL: /usr/local/etc/config.xml is missing - opnsense-bootstrap.sh failed."
    exit 1
fi

# =============================================
# Configure network interfaces
# =============================================

# Set correct interface names. ${NIC_PREFIX} là vtnet với cả libvirt lẫn
# VirtualBox vì hai provider đều gắn NIC virtio.
# Máy ảo chỉ có hai card, cả hai provider đều đặt NAT của mình lên vị trí đầu:
#   ${NIC_PREFIX}0 = NAT của provider -> WAN (DHCP). `vagrant ssh` đi đường này,
#                    và đây cũng là lối ra Internet để pkg tải gói.
#   ${NIC_PREFIX}1 = host-only       -> LAN tĩnh ${VIRTUAL_MACHINE_IP}, Web UI.
# config.xml của OPNsense đánh dấu LAN là mismatch0 và WAN là mismatch1.
sed -i '' -e "s/mismatch0/${NIC_PREFIX}1/" /usr/local/etc/config.xml
sed -i '' -e "s/mismatch1/${NIC_PREFIX}0/" /usr/local/etc/config.xml

# Remove IPv6 configuration from WAN
sed -i '' -e '/<ipaddrv6>dhcp6<\/ipaddrv6>/d' /usr/local/etc/config.xml

# Remove IPv6 configuration from LAN
sed -i '' -e '/<ipaddrv6>track6<\/ipaddrv6>/d' /usr/local/etc/config.xml
sed -i '' -e '/<subnetv6>64<\/subnetv6>/d' /usr/local/etc/config.xml
sed -i '' -e '/<track6-interface>wan<\/track6-interface>/d' /usr/local/etc/config.xml
sed -i '' -e '/<track6-prefix-id>0<\/track6-prefix-id>/d' /usr/local/etc/config.xml

# Change OPNsense LAN IP addresses
sed -i '' -e "s/192\.168\.1\.1</${VIRTUAL_MACHINE_IP}</" /usr/local/etc/config.xml

# Change DHCP range to match LAN IP address
lan_net=$(echo "${VIRTUAL_MACHINE_IP}" | sed 's/\.[0-9]*$//')
sed -i '' -e "s/192\.168\.1\./${lan_net}./" /usr/local/etc/config.xml

# =============================================
# Configure SSH and user access
# =============================================

# Enable SSH by default
sed -i '' -e '/<group>admins<\/group>/r files/ssh.xml' /usr/local/etc/config.xml

# Allow SSH on all interfaces
sed -i '' -e '/<filter>/r files/filter.xml' /usr/local/etc/config.xml

# Do not block private networks on WAN
sed -i '' -e '/<blockpriv>1<\/blockpriv>/d' /usr/local/etc/config.xml

# Reset shell of Vagrant user
/usr/sbin/pw usermod vagrant -s /bin/sh

# Create XML config for Vagrant user
key=$(b64encode -r dummy <.ssh/authorized_keys | tr -d '\n')
echo "      <authorizedkeys>${key}</authorizedkeys>" >files/vagrant2.xml
cat files/vagrant[123].xml >files/vagrant.xml

# Add Vagrant user - OPNsense style
sed -i '' -e '/<\/member>/r files/admins.xml' /usr/local/etc/config.xml
sed -i '' -e '/<\/user>/r files/vagrant.xml' /usr/local/etc/config.xml

# Change home directory to group nobody
# chgrp -R nobody /usr/home/vagrant

# Change sudoers file to reference user instead of group
sed -i '' -e 's/^%//' /usr/local/etc/sudoers.d/vagrant

# Display helpful message for the user
echo '#####################################################'
echo '#                                                   #'
echo '#  OPNsense provisioning finished - shutting down.  #'
echo '#  Use `vagrant up` to start your OPNsense.         #'
echo '#                                                   #'
echo '#####################################################'

# Shutdown the system
shutdown -p now
