# Entry point — dispatch only. Do NOT put settings here.
#
#   Shared configuration     -> vagrant/common.rb
#   Provider-specific config -> vagrant/<provider>.rb
#
# Use:  vagrant up                             # libvirt/KVM (default)
#       PROVIDER=virtualbox vagrant up
#       PROVIDER=vmware vagrant up

provider = ENV.fetch('PROVIDER', 'libvirt').downcase
provider = 'libvirt'    if provider == 'kvm'
provider = 'virtualbox' if provider == 'vbox'
provider = 'vmware'     if %w[vmw vmware_desktop vmware_workstation vmware_fusion].include?(provider)
unless %w[libvirt virtualbox vmware].include?(provider)
  abort "==> Unknown PROVIDER=#{provider.inspect}. Expected: libvirt | virtualbox | vmware"
end

# The provider file must load first: it defines opnsense_wan_network,
# opnsense_nic_prefix and opnsense_provider_config, which opnsense_common calls.
require_relative "vagrant/#{provider}"
require_relative 'vagrant/common'

# Make `PROVIDER=virtualbox vagrant up` select VirtualBox without also
# having to pass --provider=.
# The plugin registers itself as `vmware_desktop`, not `vmware`.
ENV['VAGRANT_DEFAULT_PROVIDER'] ||= provider == 'vmware' ? 'vmware_desktop' : provider

Vagrant.configure(2) { |config| opnsense_common(config) }
