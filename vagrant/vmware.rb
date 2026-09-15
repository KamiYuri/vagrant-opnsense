# OPNsense Vagrant — VMware Workstation / Fusion provider specifics.
#
# Requires:
#       - VMware Workstation Pro 17+ (Windows, Linux) hoặc VMware Fusion (macOS)
#       - Vagrant VMware Utility (gói cài riêng, tải từ trang Vagrant)
#       - vagrant plugin install vagrant-vmware-desktop
#
# Everything not defined here is shared and lives in vagrant/common.rb.

# WAN NIC (guest vmx2). Declared by common.rb in the slot that fixes the
# guest interface order bootstrap.sh depends on.
# Bỏ trống WAN_BRIDGE thì VMware tự chọn interface cho cầu nối.
def opnsense_wan_network(config, bridge_dev)
  if bridge_dev.to_s.empty?
    config.vm.network 'public_network'
  else
    config.vm.network 'public_network', bridge: bridge_dev
  end
end

# Tên card mạng trong guest: VMware không có virtio. Khối provider bên dưới ép
# toàn bộ NIC sang vmxnet3, FreeBSD đặt tên chúng là vmx0..vmx4.
def opnsense_nic_prefix
  'vmx'
end

# vagrant-vmware-desktop gắn NIC NAT (vmnet8) làm adapter đầu tiên cho
# `vagrant ssh`; bootstrap.sh nối nó vào OPNsense thành OPT1 "MGMT".
def opnsense_provider_config(config)
  config.vm.provider :vmware_desktop do |v|
    v.gui                        = false
    v.vmx['memsize']             = $vm_memory.to_s
    v.vmx['numvcpus']            = $vm_cpus.to_s
    v.vmx['cpuid.coresPerSocket'] = '1'

    # Ép vmxnet3 cho cả 5 adapter để tên interface trong guest là vmx0..vmx4.
    # Mặc định của provider là e1000e, khi đó guest sẽ đặt tên em0..em4 và
    # opnsense_nic_prefix ở trên không còn đúng.
    (0..4).each { |i| v.vmx["ethernet#{i}.virtualDev"] = 'vmxnet3' }
  end

  # vagrant-disksize chỉ hỗ trợ VirtualBox, không có đường tương đương cho
  # vmware_desktop: đĩa giữ nguyên kích thước mà box mang theo. Cần thêm dung
  # lượng thì mở rộng đĩa trong VMware rồi `gpart resize` + `zpool online -e`
  # bên trong guest.
  puts '==> NOTE: provider vmware_desktop giữ nguyên dung lượng đĩa của box (không có vagrant-disksize).'
end
