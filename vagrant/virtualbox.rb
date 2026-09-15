# OPNsense Vagrant — VirtualBox provider specifics.
#
# Requires:
#       - VirtualBox >= 7.0.4
#       - vagrant plugin install vagrant-disksize  (for disk resizing below)
#
# Everything not defined here is shared and lives in vagrant/common.rb.

# Tên card mạng trong guest: hai NIC bị ép sang virtio bên dưới -> vtnet0, vtnet1.
def opnsense_nic_prefix
  'vtnet'
end

# VirtualBox tự gắn card NAT của nó làm NIC đầu tiên (vtnet0) cho `vagrant ssh`;
# bootstrap.sh nối card này vào OPNsense thành WAN.
# LAN dùng mạng host-only trong dải 192.168.56.0/21 — tránh 192.168.56.1 vì
# VirtualBox giữ địa chỉ đó cho host.
def opnsense_provider_config(config)
  config.vm.provider :virtualbox do |vb|
    vb.memory = $vm_memory
    vb.cpus   = $vm_cpus

    # Ép virtio để tên card trong guest đúng thứ bootstrap.sh chờ đợi
    # (vtnet0, vtnet1). Mặc định e1000 của VirtualBox sẽ đặt tên em0, em1.
    vb.customize ['modifyvm', :id, '--nictype1', 'virtio']
    vb.customize ['modifyvm', :id, '--nictype2', 'virtio']
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
