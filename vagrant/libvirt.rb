# OPNsense Vagrant — Libvirt (KVM) provider specifics.
#
# Requires the vagrant-libvirt plugin:
#       vagrant plugin install vagrant-libvirt
#
# Everything not defined here is shared and lives in vagrant/common.rb.

# Tên card mạng trong guest: libvirt gắn NIC virtio -> vtnet0, vtnet1.
def opnsense_nic_prefix
  'vtnet'
end

# Libvirt tự gắn một mạng NAT quản trị làm card đầu tiên (vtnet0 trong guest);
# bootstrap.sh nối nó vào OPNsense thành WAN, và `vagrant ssh` cũng đi đường này.
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
