# Entry point — dispatch only. Do NOT put settings here.
#
#   Shared configuration     -> vagrant/common.rb
#   Provider-specific config -> vagrant/<provider>.rb
#
# Use:  vagrant up                      # VirtualBox, mặc định trên mọi hệ điều hành
#       PROVIDER=libvirt vagrant up     # libvirt/KVM, chỉ chạy trên Linux

provider = ENV.fetch('PROVIDER', 'virtualbox').downcase
provider = 'libvirt'    if provider == 'kvm'
provider = 'virtualbox' if provider == 'vbox'
unless %w[libvirt virtualbox].include?(provider)
  abort "==> PROVIDER=#{provider.inspect} không dùng được. Chỉ nhận: libvirt | virtualbox"
end

# In ra provider đang dùng. Quên đặt biến, hoặc đặt sai cú pháp shell, thì nhìn
# dòng này là biết ngay thay vì đợi một thông báo lỗi khó lần ở cuối.
puts "==> PROVIDER = #{provider}"
if provider == 'virtualbox' && ENV['PROVIDER'].to_s.empty? && Vagrant::Util::Platform.linux?
  puts '    Trên Linux, libvirt nhanh hơn đáng kể: PROVIDER=libvirt vagrant up'
end

# The provider file must load first: it defines opnsense_nic_prefix and
# opnsense_provider_config, which opnsense_common calls.
require_relative "vagrant/#{provider}"
require_relative 'vagrant/common'

# Make `PROVIDER=libvirt vagrant up` select libvirt without also having to pass
# --provider=.
ENV['VAGRANT_DEFAULT_PROVIDER'] ||= provider

Vagrant.configure(2) { |config| opnsense_common(config) }
