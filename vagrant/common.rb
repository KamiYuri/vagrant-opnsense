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
  #   nfs   - hai chiều, phản ánh sửa đổi ngay lập tức; host phải có NFS server
  #           (Linux, macOS). Đây là mặc định.
  #   rsync - một chiều host -> guest; dùng khi host là Windows vì Windows không
  #           có sẵn NFS server. Đẩy thay đổi bằng `vagrant rsync`, hoặc để
  #           `vagrant rsync-auto` chạy nền.
  # Ép kiểu khác mặc định bằng SYNC_TYPE=nfs|rsync.
  #
  $sync_type = ENV.fetch('SYNC_TYPE', Vagrant::Util::Platform.windows? ? 'rsync' : 'nfs').downcase
  unless %w[nfs rsync].include?($sync_type)
    raise "SYNC_TYPE phải là 'nfs' hoặc 'rsync' (nhận được: '#{$sync_type}')"
  end
  puts "==> SYNC_TYPE = #{$sync_type}"

  # NTFS không mang bit thực thi của Unix, nên mọi file đi qua rsync từ Windows
  # đến guest với quyền do cygwin/msys suy đoán. Ép cứng thư mục 755 / file 755:
  # Mk/core.mk cài đặt bằng `tar` nên mode của cây nguồn đi thẳng vào
  # /usr/local, và 424 file trong core (src/opnsense/scripts, src/etc/rc.d,
  # src/sbin...) cần bit thực thi để configd gọi được.
  #
  # Cây mã nguồn OPNsense (core/, plugins/, ports/, src/, tools/, update/) được
  # clone vào /var/vagrant TỪ TRONG GUEST theo hướng dẫn phát triển ở README.
  # Phía host không có chúng, nên `--delete` ở lần rsync kế tiếp sẽ xoá sạch nếu
  # không loại trừ. Danh sách này phải khớp với .gitignore.
  $rsync_opts = {
    type: 'rsync',
    rsync__exclude: ['.git/', '.vagrant/', 'work/', 'tmp/', '*.box',
                     'core/', 'plugins/', 'ports/', 'src/', 'tools/', 'update/'],
    rsync__args: ['--verbose', '--archive', '--delete', '--compress',
                  '--copy-links', '--chmod=Du=rwx,Dgo=rx,Fu=rwx,Fgo=rx']
  }
  $nfs_opts   = { type: 'nfs', nfs_udp: false }
  $sync_opts  = $sync_type == 'rsync' ? $rsync_opts : $nfs_opts

  # Disable the default /vagrant share; mount our own.
  config.vm.synced_folder '.', '/vagrant', id: 'vagrant-root', disabled: true
  config.vm.synced_folder '.', $vagrant_mount_path, $sync_opts

  config.ssh.shell      = '/bin/sh'
  config.ssh.keep_alive = true
  config.vm.boot_timeout = 6000

  # Hide the repository's .git directory inside NFS mounts (overmount with empty
  # tmpfs). Ở chế độ rsync, .git đã nằm trong rsync__exclude nên không có gì để che.
  config.vm.provision "shell", run: "always", inline: <<-SHELL
    if [ -d "#{$vagrant_mount_path}/.git" ]; then
      mount -t tmpfs tmpfs "#{$vagrant_mount_path}/.git"
    fi
  SHELL

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
  config.vm.network 'private_network', type: 'dhcp'
  config.vm.network 'private_network', type: 'dhcp'

  #
  # Provider-specific configuration (vagrant/<provider>.rb)
  #
  opnsense_provider_config(config)

  #
  # Bootstrap OPNsense
  #
  config.vm.provision "file",  source: "files", destination: "files"

  config.vm.provision "shell", env: {
    "OPNSENSE_RELEASE"     => $opnsense_release,
    "VIRTUAL_MACHINE_IP"   => $virtual_machine_ip,
    "BOOTSTRAP_SCRIPT_URL" => $bootstrap_script_url,
    "NIC_PREFIX"           => $nic_prefix
  }, path: "bootstrap.sh"
end
