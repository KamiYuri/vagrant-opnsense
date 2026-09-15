# OPNsense Vagrant — Libvirt (KVM) provider specifics.
#
# Requires the vagrant-libvirt plugin:
#       vagrant plugin install vagrant-libvirt
#
# Everything not defined here is shared and lives in vagrant/common.rb.

# WAN NIC (guest vtnet2). Declared by common.rb in the slot that fixes the
# guest interface order bootstrap.sh depends on.
def opnsense_wan_network(config, bridge_dev)
  if bridge_dev.to_s.empty?
    config.vm.network 'public_network'
  else
    config.vm.network 'public_network', dev: bridge_dev, mode: 'bridge', type: 'direct'
  end
end

# Tên card mạng trong guest: libvirt gắn NIC virtio -> vtnet0..vtnet4.
def opnsense_nic_prefix
  'vtnet'
end

# Libvirt automatically provisions a separate management NAT used by `vagrant ssh`
# (vtnet0 in the guest); it is wired into OPNsense as OPT1 "MGMT" by bootstrap.sh.
# That keeps the management network separate from WAN traffic — `vagrant ssh`
# never rides the bridged WAN.
def opnsense_provider_config(config)
  config.vm.provider :libvirt do |lv|
    lv.memory               = $vm_memory
    lv.cpus                 = $vm_cpus
    lv.disk_bus             = 'virtio'
    lv.nic_model_type       = 'virtio'
    lv.machine_virtual_size = 64        # Disk size in GB
    lv.connect_via_ssh      = false
  end
end
