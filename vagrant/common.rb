# Configuration shared by every provider.
#
# Provider-specific pieces (the config.vm.provider block, disk resizing) live in
# vagrant/<provider>.rb and are reached through opnsense_provider_config, which
# the entry-point Vagrantfile has already loaded by the time this runs.
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

  # Tài nguyên cấp cho VM, dùng chung cho cả ba provider. Mặc định nhắm tới máy
  # cá nhân 16 GB RAM: 4 GB đủ cho OPNsense (khuyến nghị của dự án là 2-4 GB) mà
  # vẫn chừa phần lớn RAM cho host, 2 core đủ cho bootstrap và vận hành thường
  # ngày. Cần build mã nguồn trong guest thì nâng tạm bằng
  # VM_MEMORY=8192 VM_CPUS=4 vagrant up.
  $vm_memory = Integer(ENV.fetch('VM_MEMORY', 4096))
  $vm_cpus   = Integer(ENV.fetch('VM_CPUS', 2))

  # Tên card mạng trong guest: cả libvirt lẫn VirtualBox đều dùng virtio nên là
  # vtnet0, vtnet1. bootstrap.sh nhận giá trị này qua NIC_PREFIX và tự dò lại
  # trong guest nếu để trống. Ép bằng NIC_PREFIX=... khi guest đặt tên khác.
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
  # Mã nguồn nằm trên host, trong thư mục core/ đặt cạnh repo này, rồi được đưa
  # vào guest tại $vagrant_mount_path/core. Guest chỉ biên dịch và chạy.
  #
  #   <thư mục làm việc>/
  #   ├── vagrant-opnsense/   repo này
  #   └── core/               opnsense/core, nhánh stable/<release>
  #
  # vboxsf không chạy trên FreeBSD, nên chỉ còn hai cơ chế:
  #   nfs  - hai chiều, sửa trên host là guest thấy ngay; host phải có NFS
  #          server (Linux, macOS). Mặc định ngoài Windows.
  #   none - Vagrant không gắn gì. Mặc định trên Windows, nơi không có NFS
  #          server: extension BKCSFTP của VS Code đẩy file sang mỗi lần lưu.
  # Ép kiểu khác mặc định bằng SYNC_TYPE=nfs|none.
  #
  $sync_type = ENV.fetch('SYNC_TYPE', Vagrant::Util::Platform.windows? ? 'none' : 'nfs').downcase
  unless %w[nfs none].include?($sync_type)
    raise "SYNC_TYPE phải là 'nfs' hoặc 'none' (nhận được: '#{$sync_type}')"
  end
  puts "==> SYNC_TYPE = #{$sync_type}"

  # Đường dẫn tuyệt đối tới cây mã nguồn trên host, để kiểm tra sự tồn tại.
  # __dir__ là thư mục vagrant/ nên lùi hai cấp mới ra ngang hàng với repo.
  $core_path = File.expand_path('../../core', __dir__)

  # Disable the default /vagrant share; mount our own when a mechanism exists.
  config.vm.synced_folder '.', '/vagrant', id: 'vagrant-root', disabled: true
  if $sync_type == 'nfs'
    if File.directory?($core_path)
      config.vm.synced_folder '../core', "#{$vagrant_mount_path}/core",
                              type: 'nfs', nfs_udp: false
    else
      puts "==> Không thấy #{$core_path}"
      puts "    Clone opnsense/core vào đó rồi chạy lại. Xem README."
    end
  else
    puts "==> Vagrant không gắn #{$vagrant_mount_path}. Đẩy mã nguồn từ host sang"
    puts "    guest bằng extension BKCSFTP của VS Code: vagrant ssh-config"
  end

  config.ssh.shell      = '/bin/sh'
  config.ssh.keep_alive = true
  config.vm.boot_timeout = 6000

  # Hai thư mục trong cây mã nguồn cần được che khỏi guest.
  #
  #   work            thư mục làm việc của `make mount`: mount_unionfs và file
  #                   tạm chỉ có nghĩa bên trong guest, không được đi ra host.
  #   src/etc/sudoers.d
  #                   `make mount` phủ src/ lên /usr/local, nên thư mục này
  #                   thành /usr/local/etc/sudoers.d và mang quyền sở hữu của
  #                   cây mã nguồn. sudo chỉ đọc sudoers.d khi thư mục thuộc
  #                   root; thuộc user khác thì nó bỏ qua cả thư mục, kéo theo
  #                   mất luôn file `vagrant` mà bootstrap.sh đã dựng, và
  #                   `sudo` trong guest bắt đầu hỏi mật khẩu. Phủ tmpfs rỗng
  #                   thuộc root lên là xong; file duy nhất bên trong
  #                   (src/etc/sudoers.d/opnsense) upstream đã đánh dấu
  #                   OBSOLETE, gỡ trong 26.7.
  #
  # Ở chế độ nfs, phủ tmpfs lên cả hai. Ở chế độ none, work chỉ cần tạo sẵn vì
  # `make mount` touch work/.mount_done chứ không tự tạo thư mục, còn
  # src/etc/sudoers.d thì đã bị loại ngay từ `ignore` trong .vscode/sftp.json.
  if $sync_type == 'nfs'
    config.vm.provision "shell", run: "always", inline: <<-SHELL
      if [ -d "#{$vagrant_mount_path}/core" ]; then
        mkdir -p "#{$vagrant_mount_path}/core/work"
        mount | grep -q " on #{$vagrant_mount_path}/core/work " || mount -t tmpfs tmpfs "#{$vagrant_mount_path}/core/work"
        if [ -d "#{$vagrant_mount_path}/core/src/etc/sudoers.d" ]; then
          mount | grep -q " on #{$vagrant_mount_path}/core/src/etc/sudoers.d " || mount -t tmpfs tmpfs "#{$vagrant_mount_path}/core/src/etc/sudoers.d"
        fi
      fi
    SHELL
  else
    config.vm.provision "shell", run: "always", inline: <<-SHELL
      mkdir -p "#{$vagrant_mount_path}/core/work"
      chown vagrant:vagrant "#{$vagrant_mount_path}" "#{$vagrant_mount_path}/core" "#{$vagrant_mount_path}/core/work"
    SHELL
  end

  #
  # Network — đúng hai card, không cầu nối ra mạng vật lý
  #
  #   <prefix>0  NAT của provider, do provider tự gắn vào vị trí đầu.
  #              bootstrap.sh nối nó vào OPNsense thành WAN (DHCP); đây cũng là
  #              đường mà `vagrant ssh` đi.
  #   <prefix>1  host-only, LAN tĩnh $virtual_machine_ip, nơi đặt Web UI.
  #
  # Thứ tự khai báo quyết định thứ tự card trong guest và bootstrap.sh bám theo
  # đúng thứ tự đó — không đảo, không chèn thêm.
  #
  config.vm.network 'private_network', ip: $virtual_machine_ip, auto_config: false

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
