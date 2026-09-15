# OPNsense Development Environment

A Vagrant-based OPNsense development environment. It automates the bootstrapping, networking, and
configuration required to locally test and develop features for OPNsense.

<details>
<summary><strong>Table of Contents</strong></summary>

- [Overview](#overview)
- [Vagrant Primer](#vagrant-primer)
- [Architecture & Bootstrapping Mechanism](#architecture--bootstrapping-mechanism)
- [Prerequisites](#prerequisites)
- [Environment Configuration](#environment-configuration)
- [Deployment (Getting Started)](#deployment-getting-started)
- [Access and Workflow](#access-and-workflow)
- [Troubleshooting & Maintenance](#troubleshooting--maintenance)
</details>

---

## Overview

The primary goal of this Vagrant environment is to abstract away the complexity of configuring a
reliable, isolated FreeBSD-based OPNsense instance for software development. By using Libvirt (KVM),
VirtualBox, or VMware as the provider, developers receive a uniform testing environment regardless of
their host system OS.

## Vagrant Primer

New to Vagrant? It is a command-line tool that builds a virtual machine from a text file. Instead of clicking through a hypervisor GUI and writing down the steps afterwards, you describe the machine once — in the `Vagrantfile` — and everyone runs `vagrant up` to get an identical VM.

Five terms cover almost everything used here:

| Term | What it means in this project |
| --- | --- |
| **Box** | The base image Vagrant starts from: `BKCS/FreeBSD-15.1-ZFS`, a plain FreeBSD install. OPNsense is layered on top afterwards. |
| **Provider** | The hypervisor that actually runs the VM — Libvirt/KVM, VirtualBox, or VMware (see below). |
| **Provisioner** | A script Vagrant executes *inside* the guest after boot. Here it is [`bootstrap.sh`](bootstrap.sh), which converts the FreeBSD box into an OPNsense appliance. |
| **Synced folder** | A host directory mounted into the guest. This repository is mounted at `/var/vagrant`, so edits made on your host are visible in the VM immediately. |
| **`.vagrant/`** | Local, gitignored state: which VM belongs to this directory, which provider created it, the generated SSH key. It is managed for you — remove it through `vagrant destroy`, not by hand. |

Day-to-day lifecycle:

```bash
vagrant up          # create the VM the first time, or boot an existing one
vagrant ssh         # shell into the guest as the `vagrant` user
vagrant halt        # graceful shutdown
vagrant reload      # halt + up, picking up Vagrantfile changes
vagrant provision   # re-run bootstrap.sh on a machine that is already running
vagrant status      # is it running, and under which provider?
vagrant destroy -f  # delete the VM; the next `vagrant up` rebuilds from scratch
```

Every command is scoped to the directory holding the `Vagrantfile`, so run them from the repository root. All tuning happens through environment variables rather than CLI flags — see [Environment Configuration](#environment-configuration).

### Which provider?

A **provider** is the hypervisor Vagrant drives. The VM description is identical either way; only the plumbing differs, which is why provider-specific settings are isolated in [`vagrant/libvirt.rb`](vagrant/libvirt.rb), [`vagrant/virtualbox.rb`](vagrant/virtualbox.rb) and [`vagrant/vmware.rb`](vagrant/vmware.rb).

| | Libvirt / KVM (default) | VirtualBox | VMware Desktop |
| --- | --- | --- | --- |
| Host OS | Linux only | Linux, Windows, macOS (Intel) | Linux, Windows, macOS |
| Nature | Virtualization built into the Linux kernel | Standalone application installed on top of the OS | Standalone application installed on top of the OS |
| Performance | Faster; near-native I/O through virtio | Slower and heavier on the host | Fast; paravirtualized vmxnet3 NICs |
| Required plugin | `vagrant-libvirt` | `vagrant-disksize` (otherwise the disk stays at the box default instead of 64 GB) | `vagrant-vmware-desktop` + Vagrant VMware Utility |
| Bridged WAN | Picks an interface automatically, or set `WAN_BRIDGE` | Prompts you to choose one unless `WAN_BRIDGE` is set | Picks an interface automatically, or set `WAN_BRIDGE` |
| Guest NIC names | `vtnet0`..`vtnet4` (virtio) | `vtnet0`..`vtnet4` (NICs forced to virtio) | `vmx0`..`vmx4` (vmxnet3) |
| Disk resizing | `64` GB via `machine_virtual_size` | `64` GB via `vagrant-disksize` | Not supported — box default is kept |

The defaults target a personal machine with 16 GB of RAM: 4 GB and 2 vCPUs for the guest, which
leaves the host comfortable. OPNsense itself is happy with 2-4 GB; raise both temporarily with
`VM_MEMORY=8192 VM_CPUS=4 vagrant up` when you need to build sources inside the guest. The 64 GB
disk is sparse — it grows as used, not up front.

The box uses ZFS, so enlarging the virtual disk does not enlarge the pool by itself: after a
resize, run `gpart resize` on the partition and `zpool online -e zroot <dev>` inside the guest.

Choose Libvirt on Linux: it is the default and the better-tested path here. Choose VirtualBox or VMware on Windows or macOS, or wherever KVM is unavailable — for instance inside a VM that does not expose nested virtualization. Select one per command with `PROVIDER=virtualbox vagrant up`.

They cannot share state: `.vagrant/` records which provider built the machine, so switching providers requires `vagrant destroy -f` first.

## Architecture & Bootstrapping Mechanism

This environment utilizes a layered deployment architecture:

1. **Base OS:** Provisions a plain `BKCS/FreeBSD-15.1-ZFS` Vagrant box.
2. **Bootstrapping Script:** Vagrant provisions this repository's `bootstrap.sh` inside the guest.
   That script downloads `opnsense-bootstrap.sh.in` from
   [`opnsense/update`](https://github.com/opnsense/update) (branch `master`) and runs it with
   `-r $opnsense_release -y`.
3. **Core Sources:** `opnsense-bootstrap.sh` derives the core branch from the release on its own —
   `-r 26.7` resolves to the `stable/26.7` branch of
   [`opnsense/core`](https://github.com/opnsense/core) — and downloads it from GitHub. Account
   (`opnsense`) and repository (`core`) are the script's own defaults, so nothing needs to be passed.
4. **Packages:** Fetched from upstream `https://pkg.opnsense.org`.

Upon completion of the bootstrap script, the VM configures the necessary network interfaces, enables SSH by default, and halts. A second `vagrant up` brings up a fully functional OPNsense gateway.

`bootstrap.sh` applies two patches to the downloaded script before running it: it strips the trailing
`reboot` (Vagrant needs to stay in control of the lifecycle) and removes the `pkg unlock` call, which
errors out due to [freebsd/pkg#2278](https://github.com/freebsd/pkg/issues/2278). Neither is harmful
if upstream changes — no packages are locked here.

## Prerequisites

Before beginning, ensure the following tools are installed on your host machine:

### Universal Requirements
- [Vagrant](https://www.vagrantup.com) (>= `2.3.4`)

### Base Box

This project uses a prepared FreeBSD 15.1 (ZFS) box that is **not** published on Vagrant Cloud, so
`vagrant up` cannot fetch it for you. Add it by hand once, before the first deployment.

**1. Download the file for your provider**

| Provider | Box file |
| --- | --- |
| Libvirt / KVM | [FreeBSD-15.1-ZFS (libvirt)](https://drive.google.com/file/d/1TtTR1gZeYQHqSiYWipykPuZviBo_0Dnz/view?usp=drive_link) |
| VirtualBox | [FreeBSD-15.1-ZFS (virtualbox)](https://drive.google.com/file/d/1NtG_MhTECYVL-aQN5bNEeH-jkEu0P99W/view?usp=drive_link) |
| VMware Desktop | [FreeBSD-15.1-ZFS (vmware)](https://drive.google.com/file/d/1NZwfUyubrAUnc2spcZBZJOxCKrZ-CIRE/view?usp=drive_link) |

Download through a browser. Google Drive answers these links with a confirmation page rather than
the file itself, so handing the link straight to `vagrant box add <url>` does not work. A file this
size also triggers the "can't scan for viruses" warning — choose **Download anyway**.

**2. Register it under the name the Vagrantfile expects**

The name must match `config.vm.box` in [`vagrant/common.rb`](vagrant/common.rb) exactly:

```bash
vagrant box add --name BKCS/FreeBSD-15.1-ZFS /path/to/downloaded.box
```

On Windows, quote the path if it contains spaces:

```powershell
vagrant box add --name BKCS/FreeBSD-15.1-ZFS "C:\Users\<you>\Downloads\FreeBSD-15.1-ZFS.box"
```

Add `--provider <libvirt|virtualbox|vmware_desktop>` if Vagrant cannot work out the provider from
the file itself.

**3. Confirm it landed**

```bash
vagrant box list
# BKCS/FreeBSD-15.1-ZFS (virtualbox, 0)
```

Each provider needs its own file, but they all register under the same name — Vagrant keeps one
entry per provider, and `PROVIDER=<...> vagrant up` picks the matching one. Repeat these steps for
every provider you plan to use.

### Provider-Specific Requirements

**For VirtualBox Users:**
- [VirtualBox](https://www.virtualbox.org) (>= `7.0.4`)
- The `vagrant-disksize` plugin:
  ```bash
  vagrant plugin install vagrant-disksize
  ```

**For Libvirt (KVM) Users:**
- The `vagrant-libvirt` plugin:
  ```bash
  vagrant plugin install vagrant-libvirt
  ```

**For VMware Users:**
- VMware Workstation Pro 17+ (Windows, Linux) or VMware Fusion (macOS)
- The Vagrant VMware Utility (a separate download from the Vagrant site)
- The `vagrant-vmware-desktop` plugin:
  ```bash
  vagrant plugin install vagrant-vmware-desktop
  ```

## Environment Configuration

Shared configuration lives in a single file, [`vagrant/common.rb`](vagrant/common.rb). Provider-specific settings live in [`vagrant/libvirt.rb`](vagrant/libvirt.rb), [`vagrant/virtualbox.rb`](vagrant/virtualbox.rb) and [`vagrant/vmware.rb`](vagrant/vmware.rb); the root `Vagrantfile` only dispatches between them and holds no settings.

| Variable | Description | Default Value |
| --- | --- | --- |
| `PROVIDER` | Virtualization provider, read by the entry-point `Vagrantfile`: `libvirt` (alias `kvm`), `virtualbox` (alias `vbox`), or `vmware`. Any other value aborts `vagrant up`. | `libvirt` |
| `OPNSENSE_RELEASE` | The target OPNsense version, passed to `opnsense-bootstrap -r`. The core branch follows from it (`26.7` → `stable/26.7`). | `26.7` |
| `BOOTSTRAP_SCRIPT_URL` | Absolute URL of `opnsense-bootstrap.sh.in`. Set this to mirror the bootstrap script on an internal HTTP server. | `https://raw.githubusercontent.com/opnsense/update/master/src/bootstrap/opnsense-bootstrap.sh.in` |
| `WAN_BRIDGE` | Host interface that the WAN NIC bridges onto (e.g. `eth0`, `wlan0`, `br0`). Leave empty to let Libvirt/VMware auto-select or VirtualBox prompt at `vagrant up`. | empty |
| `NIC_PREFIX` | Guest network interface name prefix. Derived from the provider (`vtnet` for virtio, `vmx` for vmxnet3); `bootstrap.sh` re-detects it inside the guest if empty. Set it only when a provider names interfaces unexpectedly. | provider-dependent |
| `VM_MEMORY` | RAM for the guest, in MB. Applies to every provider. | `4096` |
| `VM_CPUS` | Virtual CPUs for the guest. Applies to every provider. | `2` |
| `SYNC_TYPE` | Synced-folder mechanism: `nfs` (two-way, needs an NFS server on the host) or `rsync` (one-way host → guest; push with `vagrant rsync`). | `rsync` on Windows, `nfs` elsewhere |
| `$virtual_machine_ip` | The fixed IP address assigned to the LAN interface. Edit in `vagrant/common.rb`. | `192.168.56.56` |
| `$vagrant_mount_path` | Absolute path inside the VM mapped to the host directory. Edit in `vagrant/common.rb`. | `/var/vagrant` |

### Network Topology

The virtual machine is provisioned with 5 network interfaces. Guest interface order is the same for every provider (provider-managed NAT first, then Vagrantfile declarations in order). Names are `vtnet*` under Libvirt/VirtualBox and `vmx*` under VMware:

| Guest NIC | Role     | Provided by                                                 |
| --------- | -------- | ----------------------------------------------------------- |
| `vtnet0`  | **MGMT** | Provider-managed NAT (libvirt `vagrant-libvirt` / VBox NAT / VMware vmnet8) — `vagrant ssh` lands here; wired into OPNsense as OPT1 "MGMT" (DHCP). |
| `vtnet1`  | **LAN**  | Host-only/private network, static `192.168.56.56`. Web UI lives here. |
| `vtnet2`  | **WAN**  | Bridge to the host's physical LAN (`public_network`). Override the bridge device with `WAN_BRIDGE=<iface>`. Receives DHCP from the upstream LAN — reachable from other machines on that LAN. |
| `vtnet3`  | OPT      | Private DHCP. Reserved for custom internal routing and testing. |
| `vtnet4`  | OPT      | Private DHCP. Reserved for custom internal routing and testing. |

* **VirtualBox:** LAN relies on the host-only IP range `192.168.56.0/21`. Avoid using `.1`, as it is reserved. If `WAN_BRIDGE` is unset, VirtualBox will prompt interactively for the bridge interface.
* **Libvirt:** Keeps the dedicated management network (`vagrant-libvirt`) separate from WAN traffic — `vagrant ssh` always uses the management NAT, never the bridged WAN.

A dynamic gateway `MGMT_GW` ([`files/mgmt_gw.xml`](files/mgmt_gw.xml)) is registered on the MGMT interface, since it backs the management NAT that `vagrant ssh` uses. Default Internet traffic still egresses via the bridged WAN.

## Deployment (Getting Started)

The repository layout:

| File                      | Role                                                          |
| ------------------------- | ------------------------------------------------------------- |
| `Vagrantfile`             | Entry point. Dispatch only — selects the provider, no settings. |
| `vagrant/common.rb`       | All configuration shared by every provider.                     |
| `vagrant/libvirt.rb`      | Libvirt/KVM provider block and bridged-WAN syntax.              |
| `vagrant/virtualbox.rb`   | VirtualBox provider block, virtio NICs, disk resizing.          |
| `vagrant/vmware.rb`       | VMware Desktop provider block, vmxnet3 NICs.                    |
| `bootstrap.sh`            | In-guest provisioner: runs `opnsense-bootstrap.sh`, then rewrites `config.xml`. |
| `files/`                  | XML fragments merged into OPNsense's `config.xml` during provisioning. |

`Vagrantfile` picks the provider from the `PROVIDER` environment variable (default: `libvirt`; `kvm`, `vbox` and the `vmware_*` spellings are accepted aliases) and sets `VAGRANT_DEFAULT_PROVIDER` accordingly, so no `--provider=` flag is needed.

> **Before the first `vagrant up`:** register the base box as described under
> [Base Box](#base-box). Vagrant will not download it on its own, and `vagrant up` fails with
> "Box 'BKCS/FreeBSD-15.1-ZFS' could not be found" until it is added.

**Deploy via Libvirt (KVM) — default:**
```bash
vagrant up
# or, equivalently:
PROVIDER=libvirt vagrant up
```

**Deploy via VirtualBox or VMware:**
```bash
PROVIDER=virtualbox vagrant up
PROVIDER=vmware vagrant up
```

> **Note**: During the initial deployment, the virtual machine will gracefully halt itself after the bootstrap completes. **You must issue a second `vagrant up`** immediately afterward to bring the instance back online.
>
> **Switching providers on an existing checkout:** Vagrant stores per-machine state under `.vagrant/`. If you previously ran `vagrant up` with one provider and switch to another, run `vagrant destroy -f` first or you will see provider-mismatch errors.

## Access and Workflow

Once the deployment sequence is finalized and the VM is running, you can access the instance locally.

### Web Administration UI
- **URL**: [https://192.168.56.56](https://192.168.56.56)
- **Default Username**: `root`
- **Default Password**: `opnsense`

### SSH Access
To securely gain terminal access to the appliance:

```bash
vagrant ssh
```

Root-level access (`sudo`) via the `vagrant` user requires no password prompt by default.

### Development Workflow

The root of this project folder is mirrored into the VM at `/var/vagrant`, so you can edit on the
host and evaluate inside the guest immediately.

To work on the OPNsense sources themselves, clone them **from inside the guest** into that same
directory — they then land in your host filesystem too, and can be edited with host tools. See the
[OPNsense tools documentation](https://github.com/opnsense/tools) for details on the build system.

```sh
# log in to the box and become root — press [8] in the OPNsense menu for a shell
vagrant ssh
sudo su -

# install git and mark the mounted directories as safe
pkg install git
for d in core plugins ports src tools; do
  git config --global --add safe.directory /var/vagrant/$d
done

# clone the OPNsense repositories — this will take some time
cd /var/vagrant
git clone https://github.com/opnsense/tools
cd tools
env ROOTDIR=/var/vagrant make update
```

Those directories (`core/`, `plugins/`, `ports/`, `src/`, `tools/`, `update/`) are listed in both
[`.gitignore`](.gitignore) and the `rsync__exclude` list in
[`vagrant/common.rb`](vagrant/common.rb) — the latter matters, because they do not exist on the host
side of the sync and `rsync --delete` would otherwise wipe them on the next `vagrant rsync`.

## Troubleshooting & Maintenance

**Changing the LAN IP Configuration**
If `192.168.56.56` collides with your local infrastructure:
1. Turn off the active instance: `vagrant halt`.
2. Modify `$virtual_machine_ip` in [`vagrant/common.rb`](vagrant/common.rb) — one place, every provider.
3. Restart the environment: `vagrant up`.
4. Access the web interface using the newly assigned IP address.

**Changing the OPNsense release**
Set `OPNSENSE_RELEASE` (e.g. `OPNSENSE_RELEASE=26.1 vagrant up`). The core branch follows
automatically. Note that a major release expects a matching FreeBSD base — if `pkg update` fails
inside the guest with an ABI mismatch, the base box needs to be changed alongside it.

**System Rebuilds**
To completely destroy the environment and re-sync from scratch, execute:
```bash
vagrant destroy -f
PROVIDER=<libvirt|virtualbox|vmware> vagrant up
```
