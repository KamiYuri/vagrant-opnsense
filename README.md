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
- [File Permissions](#file-permissions)
- [Live mode: mount or install](#live-mode-mount-or-install)
- [sudo and the union mount](#sudo-and-the-union-mount)
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
| **Synced folder** | A host directory made available in the guest. The OPNsense sources live on the host in `core/` and reach the VM under `/var/vagrant`. On Linux and macOS that is an NFS mount, so a host edit is visible in the guest immediately. Windows has no NFS server, so VS Code uploads on save instead — see [Editing on Windows](#editing-on-windows). |
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
| `SYNC_TYPE` | How the host tree reaches the guest: `nfs` (two-way mount, needs an NFS server on the host) or `none` (Vagrant mounts nothing; VS Code uploads over SFTP). | `none` on Windows, `nfs` elsewhere |
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

The OPNsense sources are not part of this repository; `core` is cloned next to it — see
[Development Workflow](#development-workflow).

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

The sources live on the host and reach the guest at `/var/vagrant/core`. You edit with the tools
already on your machine — editor, `git`, search — and the guest only compiles and runs.

`core` sits **next to** this repository rather than inside it, so the two stay separate checkouts
with separate histories:

```
<working directory>/        ← open this folder in VS Code
├── vagrant-opnsense/       ← this repository: Vagrantfile, bootstrap.sh, files/
├── core/                   ← opnsense/core, branch stable/26.7
└── .vscode/
    └── sftp.json           ← sync configuration, per machine, not in git
```

Clone it once, from the working directory:

```bash
git clone --branch stable/26.7 https://github.com/opnsense/core.git core
```

Pin it to the release the VM runs: `stable/26.7` matches the `OPNSENSE_RELEASE` default. Neither
checkout ignores the other, because neither contains the other.

How the tree reaches the guest depends on the host:

| Host | Mechanism | What you do |
| --- | --- | --- |
| Linux, macOS | NFS mount of `../core` at `/var/vagrant/core` | Nothing. A save on the host is already visible in the guest. |
| Windows | BKCSFTP (VS Code), upload on save | Follow [Editing on Windows](#editing-on-windows) once per machine. |

Only `core` crosses over. This repository is never synced — `bootstrap.sh` and `files/` are uploaded
by the provisioner instead. `core/work/` is excluded too: it is the working directory `make mount`
builds with `mount_unionfs`, which only means anything inside the guest.

On Linux and macOS the mount is declared against `../core`, so clone it before the first
`vagrant up`. Without it Vagrant prints the path it looked in and boots the VM with nothing mounted.

Build and install from a guest shell:

```sh
vagrant ssh
sudo sh

cd /var/vagrant/core
make install    # copy src/ into /usr/local and flush the template cache
make collect    # pull changes made on the appliance back into the tree
```

`make install` is the live loop. Its recipe ends with a branch guarded by
`exists(${LOCALBASE}/opnsense/www/index.php)` and commented *"try to update the current system if it
looks like one"*, which touches `index.php` and runs `pluginctl -cq cache_flush` — the tree is
copied in and the PHP and Volt caches are dropped, so a reload of the web UI shows the change. The
copy is a `tar` pipe over 2603 files and 40 MB, a second or two on ZFS.

Restart the backend when you change what it runs:

```sh
service configd restart
```

`make mount` is the other option, and [Live mode: mount or install](#live-mode-mount-or-install)
covers when it earns its cost.

See the [OPNsense tools documentation](https://github.com/opnsense/tools) for the rest of the build
system.

### File Permissions

`make mount` overlays `src/` straight onto `/usr/local`, so the modes in the source tree become the
modes of the running system. 423 of core's 2679 files carry the execute bit, 322 of them under
`src/opnsense/scripts` — lose it and configd cannot run them.

Windows has no execute bit: every file reports as mode `0666`. On Linux and macOS this is a
non-issue, because NFS carries the host's modes through and the host checkout already has them
right. On Windows the modes have to be declared, which is what `filePermRules` in
`.vscode/sftp.json` does — the rule list is in [Editing on Windows](#editing-on-windows). A matching
rule outranks both `filePerm` and the target's existing mode, so it holds for new files and
re-applies on every upload.

The rules grant `755` by directory, covering every path in core that holds executables. A handful of
data files in those directories end up `755` as well; nothing reads that bit on them. In the other
direction the rules miss the fonts under `src/opnsense/www/themes`, which git marks `755`; they work
fine at `644`.

Do not set `filePerm` or `dirPerm` instead. Both force one mode onto everything and switch mode
preservation off entirely.

### Live mode: mount or install

`make mount` overlays `src/` onto `/usr/local` with `mount_unionfs`, so an edit is live the moment
it lands — no copy step at all. `make install` copies the tree in and flushes the caches instead.

The OPNsense [Development Workflow](https://docs.opnsense.org/development/workflow.html) page
documents `make mount` and nothing else, and one paragraph of it no longer holds: it says the boot
sequence mounts a repository left in `/root/core` "as early as possible". No such hook exists in
26.7 — the only `mount_unionfs` the shipped tree contains is in `src/etc/rc`, for live media. The
targets themselves are fine: `mount` and `umount` are byte-identical between `stable/26.7` and
`master`, so neither is deprecated in the code.

What the union costs in this environment is everything in the two sections above: the source tree
becomes the upper layer of `/usr/local`, so its ownership and its line endings become the running
system's, `work` has to exist, and writes copy up into the tree. `make install` has none of that —
files are copied as ordinary files and survive a reboot, which is also what a release does.

So: `make install` for the normal loop, and `make mount` when you are iterating on one PHP or Volt
file often enough that a second per save is worth the caveats. Never leave a mount active while
doing anything else; `make umount` first.

One thing `make install` inherits from the tree: `install-${TARGET}` runs
`tar -C ${TREE} -cf - . | tar -C <dest> -xf -`, and bsdtar extracting as root restores the owner
recorded in the archive. The synced tree belongs to `vagrant`, so parts of `/usr/local` end up
`vagrant`-owned — this time permanently rather than only while mounted. The one path where that
breaks something is `sudoers.d`, and it is already excluded from the sync, so nothing else has shown
a symptom. If something ownership-sensitive ever does:

```sh
chown -R root:wheel /usr/local/etc
```

### sudo and the union mount

`make mount` overlays `src/` onto `/usr/local`, which makes `src/etc/sudoers.d` in the source tree
become `/usr/local/etc/sudoers.d` on the running system — and a directory that comes from the upper
layer carries that layer's ownership. The synced tree belongs to the `vagrant` user, not to root.

sudo refuses to read an include directory it does not consider secure, and ownership by anyone other
than root is enough to disqualify it. sudo then skips the whole directory, `vagrant` loses the
`NOPASSWD` rule `bootstrap.sh` wrote into `/usr/local/etc/sudoers.d/vagrant`, and `sudo` starts
asking for a password nobody has. The NFS path has the same problem, where the exported files carry
the host user's uid.

So `src/etc/sudoers.d` never reaches the guest: `ignore` drops it on Windows, and the provisioner
mounts an empty root-owned tmpfs over it under NFS. Nothing is lost — the only file there is
`src/etc/sudoers.d/opnsense`, which upstream marks `OBSOLETE` and plans to delete in 26.7. The live
rules come from `/usr/local/etc/sudoers.d/20-opnsense`, rendered by configd from
`src/opnsense/service/templates/OPNsense/Auth/sudoers`, and from the box's own `vagrant` file.

To check the state on a running VM:

```sh
mount | grep unionfs
ls -ld /usr/local/etc/sudoers.d
sudo -l
```

The directory has to be `root:wheel`. If `sudo` is already refusing, `make umount` in
`/var/vagrant/core` drops the overlay and gets a working shell back.

### Editing on Windows

Windows has no NFS server, and `vboxsf` does not work on FreeBSD, so `SYNC_TYPE` defaults to `none`
there and Vagrant mounts nothing. **BKCSFTP** — the team's fork of the VS Code SFTP extension —
takes over that job: the host tree stays the original, and every save is pushed into the guest.

Install it from the `.vsix` the team distributes; it is not on the Marketplace:

```powershell
code --install-extension bkcsftp-<version>.vsix
```

Uninstall any other SFTP extension first. BKCSFTP keeps the upstream `sftp.*` command ids, so two of
them installed at once fight over those ids and files can upload twice. BKCSFTP warns when it
detects one, but removing it beforehand is simpler.

Vagrant generates the key and prints the connection details:

```powershell
vagrant ssh-config
```

Take `Port` and `IdentityFile` from that output. Open the **working directory** in VS Code — the
folder holding both `vagrant-opnsense` and `core`, not either one of them — then run
**SFTP: Config** from the command palette and replace the generated `.vscode/sftp.json` with:

```json
{
  "name": "opnsense-dev",
  "host": "127.0.0.1",
  "port": 2222,
  "protocol": "sftp",
  "username": "vagrant",
  "privateKeyPath": "vagrant-opnsense/.vagrant/machines/default/virtualbox/private_key",
  "context": "core",
  "remotePath": "/var/vagrant/core",
  "uploadOnSave": true,
  "downloadOnOpen": false,
  "useTempFile": false,
  "openSsh": false,
  "concurrency": 1,
  "watcher": {
    "files": "**/*",
    "autoUpload": true,
    "autoDelete": false
  },
  "ignore": [
    ".git",
    "work",
    "src/etc/sudoers.d"
  ],
  "filePermRules": [
    {
      "match": [
        "Scripts/**",
        "contrib/**",
        "src/etc/rc*",
        "src/etc/rc.d/**",
        "src/etc/rc.subr.d/**",
        "src/etc/rc.syshook.d/**",
        "src/etc/inc/plugins.inc.d/openvpn/**",
        "src/libexec/**",
        "src/sbin/**",
        "src/opnsense/mvc/script/**",
        "src/opnsense/scripts/**",
        "src/opnsense/service/**"
      ],
      "perm": "755"
    }
  ]
}
```

`port` comes from `vagrant ssh-config`, and the `virtualbox` segment of `privateKeyPath` follows the
provider in use.

`context` narrows the sync to `core` alone, which is why `ignore` and the `match` patterns are
written relative to `core` and this repository appears in neither. The two kinds of path resolve
from different roots: `privateKeyPath` from the folder open in VS Code, everything else from
`context`.

`uploadOnSave` covers edits made in the editor. `watcher` covers everything else that changes `core`
on disk — `git checkout`, `git pull`, a file written by another tool — so a branch switch on the
host reaches the guest without any further action.

Seed the guest once after `vagrant up`:

```
SFTP: Sync Local -> Remote
```

It walks the whole tree, which takes a few minutes; afterwards only changed files move.

> **Check where `core` resolves before that first sync.** `context` is read relative to the folder
> open in VS Code, so opening `vagrant-opnsense` instead of the working directory, or having cloned
> `core` somewhere else, sends the wrong tree — or nothing at all — into `/var/vagrant/core`.
> `autoDelete` is off, so a wrong push is not destructive, but it does leave a mixed tree in the
> guest that is easier to avoid than to clean up.
>
> Open **Output → sftp**. Loading the config logs a line starting `config at <path>` followed by the
> resolved settings; the path has to be the working directory, and `remotePath` has to read
> `/var/vagrant/core`. Then confirm the guest received the tree:
>
> ```sh
> vagrant ssh -c "ls /var/vagrant/core"
> ```
>
> The answer should list `src`, `Makefile` and the rest of core — not `Vagrantfile`, and not
> an empty directory.

Transfers run one direction only. `ignore` keeps `work` out of the picture — that directory holds
the union mounts `make mount` creates in the guest, and none of it belongs on the host. Use
`SFTP: Sync Local -> Remote` to re-push, never `SFTP: Download Folder`.

The guest still needs `work` to exist: `make mount` writes `work/.mount_done` but does not create
the directory. Since the sync never sends it, the provisioner does, on every `vagrant up`. A fresh
clone also has a `work/` on the host, holding the single file `work/.gitignore` with `*` in it,
which is how core keeps its own build output out of `git status`.

`src/etc/sudoers.d` is excluded for a different reason — see [sudo and the union
mount](#sudo-and-the-union-mount).

Files opened from the Remote Explorer are read-only previews. To edit one in place, set
`"downloadWhenOpenInRemoteExplorer": true` in `sftp.json`, or use **Edit in Local** from its context
menu. Neither is needed for the normal workflow, where the host copy is the one you edit.

A `vagrant destroy` and rebuild changes the port and the key, so `port` in `.vscode/sftp.json` has
to be updated afterwards. That file is per-machine; it lives in the working directory, outside both
git repositories.

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

**`make mount` fails on `work/.mount_done`**
`work` is excluded from the sync, so the guest gets it from the provisioner. On a VM brought up
before that provisioner existed the directory is missing, and `make mount` fails halfway:
`mount_unionfs` has already run, `touch work/.mount_done` has not. `make umount` then finds no
`.mount_done`, does nothing, and leaves the overlay in place. Clear it by hand and start again:

```sh
umount -f "<above>:/var/vagrant/core/src"
mkdir -p /var/vagrant/core/work
make mount
```

`vagrant reload` fixes it too, since the provisioner runs on every boot.

**`sudo` asks for a password after `make mount`**
`/usr/local/etc/sudoers.d` is coming from the source tree and is not root-owned — see
[sudo and the union mount](#sudo-and-the-union-mount). `make umount` restores it immediately; the
lasting fix is the `ignore` entry and the tmpfs mask, both already in place on a current checkout.

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
