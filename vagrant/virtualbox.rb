# OPNsense Vagrant — VirtualBox provider specifics.
#
# Requires:
#       - VirtualBox >= 7.0.4
#       - vagrant plugin install vagrant-disksize  (for disk resizing below)
#
# Everything not defined here is shared and lives in vagrant/common.rb.

# WAN NIC (guest vtnet2). Declared by common.rb in the slot that fixes the
# guest interface order bootstrap.sh depends on.
# If WAN_BRIDGE is unset, VirtualBox prompts interactively for the bridge.
def opnsense_wan_network(config, bridge_dev)
  if bridge_dev.to_s.empty?
    config.vm.network 'public_network'
  else
    config.vm.network 'public_network', bridge: bridge_dev
  end
end

# Tên card mạng trong guest: các NIC bị ép sang virtio bên dưới -> vtnet0..vtnet4.
def opnsense_nic_prefix
  'vtnet'
end

# VirtualBox auto-attaches its NAT adapter as the first NIC (vtnet0) for
# `vagrant ssh`; bootstrap.sh wires it into OPNsense as OPT1 "MGMT".
# LAN uses host-only network 192.168.56.0/21 — avoid 192.168.56.1 which
# VirtualBox reserves for the host.
def opnsense_provider_config(config)
  config.vm.provider :virtualbox do |vb|
    vb.memory = $vm_memory
    vb.cpus   = $vm_cpus

    # Force virtio NICs so guest interface names match those expected by bootstrap.sh
    # (sed targets vtnet0/vtnet1). VirtualBox default Intel e1000 would name them em0/em1.
    vb.customize ['modifyvm', :id, '--nictype1', 'virtio']
    vb.customize ['modifyvm', :id, '--nictype2', 'virtio']
    vb.customize ['modifyvm', :id, '--nictype3', 'virtio']
    vb.customize ['modifyvm', :id, '--nictype4', 'virtio']
    vb.customize ['modifyvm', :id, '--nictype5', 'virtio']
  end

  # Disk size (requires the vagrant-disksize plugin). Must stay outside the
  # provider block — config.disksize.size is top-level config.
  # Skipped silently if the plugin isn't installed so `vagrant up` doesn't hard-fail.
  if Vagrant.has_plugin?('vagrant-disksize')
    config.disksize.size = '64GB'
  else
    puts "==> WARN: vagrant-disksize plugin not installed — VM disk will use box default."
    puts "    Install with: vagrant plugin install vagrant-disksize"
  end
end
