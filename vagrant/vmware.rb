# OPNsense Vagrant — VMware Workstation / Fusion provider specifics.
#
# Requires:
#       - VMware Workstation Pro 17+ (Windows, Linux) hoặc VMware Fusion (macOS)
#       - Vagrant VMware Utility (gói cài riêng, tải từ trang Vagrant)
#       - vagrant plugin install vagrant-vmware-desktop
#
# Everything not defined here is shared and lives in vagrant/common.rb.

# Tên card mạng trong guest: VMware không có virtio. Khối provider bên dưới ép
# hai NIC sang vmxnet3, FreeBSD đặt tên chúng là vmx0, vmx1.
def opnsense_nic_prefix
  'vmx'
end

# vagrant-vmware-desktop gắn NIC NAT (vmnet8) làm adapter đầu tiên cho
# `vagrant ssh`; bootstrap.sh nối nó vào OPNsense thành WAN.
def opnsense_provider_config(config)
  config.vm.provider :vmware_desktop do |v|
    v.gui                        = false
    v.vmx['memsize']             = $vm_memory.to_s
    v.vmx['numvcpus']            = $vm_cpus.to_s
    v.vmx['cpuid.coresPerSocket'] = '1'

    # Ép vmxnet3 cho cả hai adapter để tên interface trong guest là vmx0, vmx1.
    # Mặc định của provider là e1000e, khi đó guest sẽ đặt tên em0, em1 và
    # opnsense_nic_prefix ở trên không còn đúng.
    (0..1).each { |i| v.vmx["ethernet#{i}.virtualDev"] = 'vmxnet3' }
  end

  # vagrant-disksize chỉ hỗ trợ VirtualBox, không có đường tương đương cho
  # vmware_desktop: đĩa giữ nguyên kích thước mà box mang theo. Cần thêm dung
  # lượng thì mở rộng đĩa trong VMware rồi `gpart resize` + `zpool online -e`
  # bên trong guest.
  puts '==> NOTE: provider vmware_desktop giữ nguyên dung lượng đĩa của box (không có vagrant-disksize).'
end
