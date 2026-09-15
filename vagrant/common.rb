# Configuration shared by every provider.
#
# Provider-specific pieces (the config.vm.provider block, the bridged-WAN
# syntax, disk resizing) live in vagrant/<provider>.rb and are reached through
# opnsense_provider_config / opnsense_wan_network, which the entry-point
# Vagrantfile has already loaded by the time this runs.
#
# All relative paths below resolve against the directory holding the
# Vagrantfile (the repository root), not this file.

def opnsense_common(config)
  #
  # General settings
  #

  # Release đích của OPNsense. opnsense-bootstrap.sh tự suy nhánh core từ giá
  # trị này (26.7 -> stable/26.7), nên đây là đầu vào duy nhất nó cần.
  $opnsense_release   = ENV.fetch('OPNSENSE_RELEASE', '26.7')

  $virtual_machine_ip = '192.168.56.56'

  # Hai cổng OPT để thử nghiệm. Mỗi cổng phải có dải riêng: provider VMware chỉ
  # tạo mạng host-only riêng khi biết subnet, còn `type: 'dhcp'` làm cả hai rơi
  # về vmnet1 mặc định và dùng chung một segment với nhau lẫn với máy ảo khác
  # trên host. Địa chỉ ở đây chỉ dùng để chọn mạng phía host; `auto_config: false`
  # giữ nguyên interface trong guest để OPNsense tự quản.
  $opt1_ip = ENV.fetch('OPT1_IP', '192.168.57.56')
  $opt2_ip = ENV.fetch('OPT2_IP', '192.168.58.56')
  $vagrant_mount_path = '/var/vagrant'
  $wan_bridge_dev     = ENV.fetch('WAN_BRIDGE', '')

  # Tài nguyên cấp cho VM, dùng chung cho cả ba provider. Mặc định nhắm tới máy
  # cá nhân 16 GB RAM: 4 GB đủ cho OPNsense (khuyến nghị của dự án là 2-4 GB) mà
  # vẫn chừa phần lớn RAM cho host, 2 core đủ cho bootstrap và vận hành thường
  # ngày. Cần build mã nguồn trong guest thì nâng tạm bằng
  # VM_MEMORY=8192 VM_CPUS=4 vagrant up.
  $vm_memory = Integer(ENV.fetch('VM_MEMORY', 4096))
  $vm_cpus   = Integer(ENV.fetch('VM_CPUS', 2))

  # Tên card mạng trong guest phụ thuộc provider: virtio -> vtnet0..4 (libvirt,
  # VirtualBox), vmxnet3 -> vmx0..4 (VMware). bootstrap.sh nhận giá trị này qua
  # NIC_PREFIX và tự dò lại trong guest nếu để trống. Ép bằng NIC_PREFIX=... khi
  # provider đặt tên card khác dự đoán.
  $nic_prefix = ENV.fetch('NIC_PREFIX', opnsense_nic_prefix)

  # URL to fetch the opnsense-bootstrap.sh.in script from. Override to mirror
  # the script on an internal HTTP server.
  $bootstrap_script_url = ENV.fetch(
    'BOOTSTRAP_SCRIPT_URL',
    'https://raw.githubusercontent.com/opnsense/update/master/src/bootstrap/opnsense-bootstrap.sh.in'
  )

  #
  # Box configuration
  #
  config.vm.box = "BKCS/FreeBSD-15.1-ZFS"

  #
  # Synced folders
  #
  # vboxsf không chạy trên FreeBSD, nên chỉ còn hai lựa chọn:
  #   nfs  - hai chiều, phản ánh sửa đổi ngay lập tức; host phải có NFS server
  #          (Linux, macOS). Đây là mặc định ngoài Windows.
  #   none - không gắn thư mục nào vào guest. Mặc định trên Windows: Windows
  #          không có NFS server, còn rsync thì một chiều và làm hỏng quyền
  #          file lẫn ký tự kết thúc dòng. Thay vào đó, sửa file trực tiếp
  #          trong guest qua SSH/SFTP (VS Code Remote-SSH) — xem README.
  # Ép kiểu khác mặc định bằng SYNC_TYPE=nfs|none.
  #
  $sync_type = ENV.fetch('SYNC_TYPE', Vagrant::Util::Platform.windows? ? 'none' : 'nfs').downcase
  unless %w[nfs none].include?($sync_type)
    raise "SYNC_TYPE phải là 'nfs' hoặc 'none' (nhận được: '#{$sync_type}')"
  end
  puts "==> SYNC_TYPE = #{$sync_type}"

  # Disable the default /vagrant share; mount our own when a mechanism exists.
  config.vm.synced_folder '.', '/vagrant', id: 'vagrant-root', disabled: true
  if $sync_type == 'nfs'
    config.vm.synced_folder '.', $vagrant_mount_path, type: 'nfs', nfs_udp: false
  else
    puts "==> Không gắn #{$vagrant_mount_path} từ host. Làm việc với mã nguồn"
    puts "    bên trong guest qua SSH/SFTP: vagrant ssh-config"
  end

  config.ssh.shell      = '/bin/sh'
  config.ssh.keep_alive = true
  config.vm.boot_timeout = 6000

  # Ở chế độ nfs: che thư mục .git của repo bên trong mount (phủ tmpfs rỗng).
  # Ở chế độ none: tạo sẵn thư mục để clone mã nguồn OPNsense vào đó.
  if $sync_type == 'nfs'
    config.vm.provision "shell", run: "always", inline: <<-SHELL
      if [ -d "#{$vagrant_mount_path}/.git" ]; then
        mount -t tmpfs tmpfs "#{$vagrant_mount_path}/.git"
      fi
    SHELL
  else
    config.vm.provision "shell", run: "always", inline: <<-SHELL
      mkdir -p "#{$vagrant_mount_path}"
    SHELL
  end

  #
  # Network — LAN (static), WAN (bridge), OPT (dhcp), OPT (dhcp)
  #
  # Declaration order IS the guest interface order, and bootstrap.sh hardcodes
  # that mapping (vtnet1=LAN, vtnet2=WAN, vtnet3/4=OPT). Do not reorder.
  # Both providers attach their own management NAT ahead of these as vtnet0;
  # bootstrap.sh wires it into OPNsense as OPT1 "MGMT".
  #
  config.vm.network 'private_network', ip: $virtual_machine_ip, auto_config: false
  opnsense_wan_network(config, $wan_bridge_dev)
  config.vm.network 'private_network', ip: $opt1_ip, auto_config: false
  config.vm.network 'private_network', ip: $opt2_ip, auto_config: false

  #
  # Provider-specific configuration (vagrant/<provider>.rb)
  #
  opnsense_provider_config(config)

  #
  # Bootstrap OPNsense
  #
  config.vm.provision "file",  source: "files", destination: "files"

  # bootstrap.sh được tải lên trước rồi mới chạy, thay cho provisioner `path:`
  # chạy thẳng file vừa upload. Bước trung gian bỏ ký tự CR: working tree trên
  # Windows vẫn có thể mang CRLF (editor lưu lại, hoặc file được tạo ngoài git),
  # và /bin/sh chết ngay dòng đầu khi gặp CR.
  config.vm.provision "file",  source: "bootstrap.sh", destination: "bootstrap.sh"

  config.vm.provision "shell", env: {
    "OPNSENSE_RELEASE"     => $opnsense_release,
    "VIRTUAL_MACHINE_IP"   => $virtual_machine_ip,
    "BOOTSTRAP_SCRIPT_URL" => $bootstrap_script_url,
    "NIC_PREFIX"           => $nic_prefix
  }, inline: <<-'SHELL'
    set -e
    cd /home/vagrant
    tr -d '\r' < bootstrap.sh > bootstrap.lf.sh
    sh bootstrap.lf.sh
  SHELL
end
