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
- [Editing on Windows](#editing-on-windows)
- [Troubleshooting & Maintenance](#troubleshooting--maintenance)
</details>

---

## Overview

The primary goal of this Vagrant environment is to abstract away the complexity of configuring a
reliable, isolated FreeBSD-based OPNsense instance for software development. By using VirtualBox or
Libvirt (KVM) as the provider, developers receive a uniform testing environment regardless of their
host system OS.

## Vagrant Primer

New to Vagrant? It is a command-line tool that builds a virtual machine from a text file. Instead of clicking through a hypervisor GUI and writing down the steps afterwards, you describe the machine once — in the `Vagrantfile` — and everyone runs `vagrant up` to get an identical VM.

Five terms cover almost everything used here:

| Term | What it means in this project |
| --- | --- |
| **Box** | The base image Vagrant starts from: `BKCS/FreeBSD-15.1-ZFS`, a plain FreeBSD install. OPNsense is layered on top afterwards. |
| **Provider** | The hypervisor that actually runs the VM — VirtualBox or Libvirt/KVM (see below). |
| **Provisioner** | A script Vagrant executes *inside* the guest after boot. Here it is [`bootstrap.sh`](bootstrap.sh), which converts the FreeBSD box into an OPNsense appliance. |
| **Synced folder** | A host directory mounted into the guest. On Linux and macOS this repository is mounted at `/var/vagrant` over NFS, so host edits are visible in the VM immediately. On Windows there is no workable mechanism, so nothing is mounted — see [Editing on Windows](#editing-on-windows). |
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

A **provider** is the hypervisor Vagrant drives. The VM description is identical either way; only the plumbing differs, which is why provider-specific settings are isolated in [`vagrant/virtualbox.rb`](vagrant/virtualbox.rb) and [`vagrant/libvirt.rb`](vagrant/libvirt.rb).

| | VirtualBox (default) | Libvirt / KVM |
| --- | --- | --- |
| Host OS | Linux, Windows, macOS (Intel) | Linux only |
| Nature | Standalone application installed on top of the OS | Virtualization built into the Linux kernel |
| Performance | Slower and heavier on the host | Faster; near-native I/O through virtio |
| Required plugin | `vagrant-disksize` (otherwise the disk stays at the box default instead of 64 GB) | `vagrant-libvirt` |
| Guest NIC names | `vtnet0`, `vtnet1` (NICs forced to virtio) | `vtnet0`, `vtnet1` (virtio) |
| Disk resizing | `64` GB via `vagrant-disksize` | `64` GB via `machine_virtual_size` |

The defaults target a personal machine with 16 GB of RAM: 4 GB and 2 vCPUs for the guest, which
leaves the host comfortable. OPNsense itself is happy with 2-4 GB; raise both temporarily with
`VM_MEMORY=8192 VM_CPUS=4 vagrant up` when you need to build sources inside the guest. The 64 GB
disk is sparse — it grows as used, not up front.

The box uses ZFS, so enlarging the virtual disk does not enlarge the pool by itself: after a
resize, run `gpart resize` on the partition and `zpool online -e zroot <dev>` inside the guest.

VirtualBox is the default because it runs everywhere. On Linux, switch to Libvirt with
`PROVIDER=libvirt vagrant up` — KVM lives in the kernel, so disk and network I/O are markedly
faster than VirtualBox on the same machine.

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
| VirtualBox | [FreeBSD-15.1-ZFS (virtualbox)](https://drive.google.com/file/d/1NtG_MhTECYVL-aQN5bNEeH-jkEu0P99W/view?usp=drive_link) |
| Libvirt / KVM | [FreeBSD-15.1-ZFS (libvirt)](https://drive.google.com/file/d/1TtTR1gZeYQHqSiYWipykPuZviBo_0Dnz/view?usp=drive_link) |

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

Add `--provider <virtualbox|libvirt>` if Vagrant cannot work out the provider from the file itself.

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

  Install this one only where VirtualBox is actually used. `vagrant-disksize` 0.1.3 builds a
  VirtualBox driver as soon as Vagrant loads its `machine_action_up` hook, before looking at which
  provider is in play, so on a host without `VBoxManage` it makes every `vagrant up` fail with
  "Vagrant could not detect VirtualBox!" — including runs under libvirt. Remove it with
  `vagrant plugin uninstall vagrant-disksize`.

**For Libvirt (KVM) Users:**
- The `vagrant-libvirt` plugin:
  ```bash
  vagrant plugin install vagrant-libvirt
  ```

## Environment Configuration

Shared configuration lives in a single file, [`vagrant/common.rb`](vagrant/common.rb). Provider-specific settings live in [`vagrant/virtualbox.rb`](vagrant/virtualbox.rb) and [`vagrant/libvirt.rb`](vagrant/libvirt.rb); the root `Vagrantfile` only dispatches between them and holds no settings.

| Variable | Description | Default Value |
| --- | --- | --- |
| `PROVIDER` | Virtualization provider, read by the entry-point `Vagrantfile`: `virtualbox` (alias `vbox`) or `libvirt` (alias `kvm`). Any other value aborts `vagrant up`. | `virtualbox` |
| `OPNSENSE_RELEASE` | The target OPNsense version, passed to `opnsense-bootstrap -r`. The core branch follows from it (`26.7` → `stable/26.7`). | `26.7` |
| `BOOTSTRAP_SCRIPT_URL` | Absolute URL of `opnsense-bootstrap.sh.in`. Set this to mirror the bootstrap script on an internal HTTP server. | `https://raw.githubusercontent.com/opnsense/update/master/src/bootstrap/opnsense-bootstrap.sh.in` |
| `NIC_PREFIX` | Guest network interface name prefix. Both providers use virtio, so it is `vtnet`; `bootstrap.sh` re-detects it inside the guest if empty. Set it only when the guest names interfaces unexpectedly. | `vtnet` |
| `VM_MEMORY` | RAM for the guest, in MB. Applies to every provider. | `4096` |
| `VM_CPUS` | Virtual CPUs for the guest. Applies to every provider. | `2` |
| `SYNC_TYPE` | Synced-folder mechanism: `nfs` (two-way, needs an NFS server on the host) or `none` (nothing mounted; edit inside the guest over SSH/SFTP). | `none` on Windows, `nfs` elsewhere |
| `$virtual_machine_ip` | The fixed IP address assigned to the LAN interface. Edit in `vagrant/common.rb`. | `192.168.56.56` |
| `$vagrant_mount_path` | Absolute path inside the VM mapped to the host directory. Edit in `vagrant/common.rb`. | `/var/vagrant` |

### Network Topology

The virtual machine is provisioned with exactly two network interfaces. Guest interface order is the
same for both providers (provider-managed NAT first, then the Vagrantfile declaration). Both attach
virtio NICs, so the guest names them `vtnet*`:

| Guest NIC | Role    | Provided by                                                 |
| --------- | ------- | ----------------------------------------------------------- |
| `vtnet0`  | **WAN** | Provider-managed NAT (VirtualBox NAT / libvirt `vagrant-libvirt`). Takes DHCP from the provider, carries outbound traffic for `pkg`, and is where `vagrant ssh` lands. |
| `vtnet1`  | **LAN** | Host-only/private network, static `192.168.56.56`. Web UI lives here. |

Nothing is bridged onto the physical network, so the appliance never appears on the office LAN and
its DHCP server stays confined to the host-only segment.

`bootstrap.sh` deletes `blockpriv` from the WAN interface — without that, OPNsense would drop the
provider's RFC1918 NAT range and `vagrant ssh` could not reach the guest. SSH is opened with a
floating pass rule from [`files/filter.xml`](files/filter.xml) for the same reason.

* **VirtualBox:** LAN relies on the host-only IP range `192.168.56.0/21`. Avoid using `.1`, as it is reserved.
* **Libvirt:** the LAN network is created on demand for the `192.168.56.0/24` subnet.

## Deployment (Getting Started)

The repository layout:

| File                      | Role                                                          |
| ------------------------- | ------------------------------------------------------------- |
| `Vagrantfile`             | Entry point. Dispatch only — selects the provider, no settings. |
| `vagrant/common.rb`       | All configuration shared by every provider.                     |
| `vagrant/virtualbox.rb`   | VirtualBox provider block, virtio NICs, disk resizing.          |
| `vagrant/libvirt.rb`      | Libvirt/KVM provider block.                                     |
| `bootstrap.sh`            | In-guest provisioner: runs `opnsense-bootstrap.sh`, then rewrites `config.xml`. |
| `files/`                  | XML fragments merged into OPNsense's `config.xml` during provisioning. |

`Vagrantfile` picks the provider from the `PROVIDER` environment variable (default: `virtualbox`; `vbox` and `kvm` are accepted aliases) and sets `VAGRANT_DEFAULT_PROVIDER` accordingly, so no `--provider=` flag is needed. It prints the resolved provider as `==> PROVIDER = ...` on every run.

> **Before the first `vagrant up`:** register the base box as described under
> [Base Box](#base-box). Vagrant will not download it on its own, and `vagrant up` fails with
> "Box 'BKCS/FreeBSD-15.1-ZFS' could not be found" until it is added.

**Deploy via VirtualBox — default:**
```bash
vagrant up
# or, equivalently:
PROVIDER=virtualbox vagrant up
```

**Deploy via Libvirt (KVM), Linux only:**
```bash
PROVIDER=libvirt vagrant up
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

On Linux and macOS the root of this project folder is mounted into the VM at `/var/vagrant` over
NFS, so you can edit on the host and evaluate inside the guest immediately.

To work on the OPNsense sources themselves, clone them **from inside the guest** into that same
directory. Under NFS they then land in your host filesystem too and can be edited with host tools;
on Windows they stay inside the guest and are reached over SFTP. See the
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

Those directories (`core/`, `plugins/`, `ports/`, `src/`, `tools/`, `update/`) are listed in
[`.gitignore`](.gitignore) so they never end up in this repository's history.

### Editing on Windows

Windows has no NFS server, and `vboxsf` does not work on FreeBSD, so `SYNC_TYPE` defaults to `none`
there: nothing is mounted and `/var/vagrant` exists only inside the guest. Edit it in place over
SSH/SFTP, which keeps a single copy of every file and leaves permissions and line endings alone.

Use the [SFTP extension by Natizyskunk](https://marketplace.visualstudio.com/items?itemName=Natizyskunk.sftp)
for VS Code. Vagrant already generates the key and prints the connection details:

```powershell
vagrant ssh-config
```

Take `Port` and `IdentityFile` from that output. Then open the repository folder in VS Code, run
**SFTP: Config** from the command palette, and replace the generated `.vscode/sftp.json` with:

```json
{
  "name": "opnsense-dev",
  "host": "127.0.0.1",
  "port": 2222,
  "protocol": "sftp",
  "username": "vagrant",
  "privateKeyPath": ".vagrant/machines/default/virtualbox/private_key",
  "remotePath": "/var/vagrant",
  "uploadOnSave": true,
  "useTempFile": false,
  "openSsh": false
}
```

The `virtualbox` segment follows the provider in use (`virtualbox` or `libvirt`), and the path is
resolved against the folder open in VS Code. The **SFTP** view in the Explorer sidebar then browses
`/var/vagrant`; a save writes straight back into the guest. `SFTP: Download Folder` pulls a
host-side copy when one is wanted for searching, and `uploadOnSave` keeps it pushed back.

A `vagrant destroy` and rebuild changes the port and the key, so `port` in `.vscode/sftp.json` has
to be updated afterwards. That file is per-machine and is gitignored.

VS Code's terminal runs on the host here, so `make mount` and `make install` are run through
`vagrant ssh`.

Changes to this repository itself are made on the host and take effect on the next `vagrant up`,
`vagrant reload`, or `vagrant provision` — `bootstrap.sh` and `files/` are uploaded by the
provisioner, not by a synced folder.

Line endings need no attention. [`.gitattributes`](.gitattributes) checks every text file out with
LF regardless of `core.autocrlf`, and the provisioner strips carriage returns anyway: `bootstrap.sh`
is uploaded and piped through `tr -d '\r'` before `/bin/sh` sees it, and the script does the same
for `files/*.xml` before merging them into `config.xml`. A file that picks up CRLF from an editor on
the host still provisions correctly.

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
PROVIDER=<virtualbox|libvirt> vagrant up
```
