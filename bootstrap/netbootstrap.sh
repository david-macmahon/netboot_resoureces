#!/bin/bash

# # `netbootstrap.sh`
#
# ## Usage
#
# ```
# netbootstrap.sh NFS_SERVER_IP NFS_SUBNET
#
# NFS_SERVER_IP is the IP address on the current host that netboot clients will
# use to mount the netboot root filesystem (and others).  This value is used
# when creating /etc/fstab in the netboot root filesystem.
#
# NFS_SUBNET is the subnet over which the netboot root filesystem (and others)
# will be NFS exported.  This value is is used when modifying /etc/exports on
# the netboot NFS server.
#
# Example: netbootstrap.sh 10.0.1.1 10.0.1.0/24
# ```
#
# The bootstrap process can be customized by setting these environment
# variables, shown here with their default values, before running
# `netbootstrap.sh`:
#
# - Which release (by codename) and architecture to target.  Technically,
# `ARCH` defaults to `$(dpkg --print-architecture)`, but if that command fails
# then the default of `amd64` is used.
#
#   ```sh
#   CODENAME="noble"
#   ARCH="amd64"
#   ```
#
# - Where to install various netboot components
#
#   ```sh
#   SRV_ROOT="/srv"
#   ```
#
# - Where to install files for TFTP
#
#   ```sh
#   TFTPBOOT_DIR="${SRV_ROOT}/tftpboot"
#   ```
#
# ## Overview
#
# Make a netbooot-able Ubuntu root file system (rootfs) directory.  This
# involves the following steps:
#
# 1. Use `debootstrap` to create a minimalistic root filesystem
#
# 2. Make the rootfs chroot-able
#    2.1 Add entries to `/etc/fstab` to mount `/proc`, `/sys`, `/dev/pts` in
#        rootfs
#    2.2 Mount `/proc`, `/sys`, and `/dev/pts` in the rootfs
#
# 3. `chroot` into rootfs and install addition packages (and remove some).
#
# 4. Add some `tmpfiles.d` files to rootfs `/etc/tmpfiles.d`.
#
# 5. Run `systemd-tmpfiles --create` in the rootfs for the new `tmpfiles.d`
#    files.
#
# 6. Setup `initramfs-tools` in rootfs and run `update-initramfs`.
#
# 7. Setup `/etc/fstab` file in rootfs.
#
# At this point rootfs is technically net bootable, but in order for clients to
# actually netboot it some additional configuration is required on the head
# node.
#
# 8. Install a few packages on the head node (that may already be installed):
#
#    - nfs-kernel-server
#    - syslinux-common
#    - pxelinux
#
# 9. Setup `/etc/exports` to export the rootfs and persistentfs
#
# 10. Copy some files to a "tftp boot" directory on the head node
#
# ## Details
#
# Here are more details about the steps mentioned in the overview above.
#
# 1. Use `debootstrap` to create a minimalistic root filesystem (rootfs)
#
# This will run `debootstrap` to create the base root filesystem if the
# destination does not exist.  If the destination does exist, then it will skip
# the `debootstrap` step and assume that it was already initialized
# appropriately.  This is to support the manual creation of the netboot root
# filesystem if desired.  Note that `netbootstrap.sh` downloads a modern
# version of `debootstrap` to avoid problems such as an old `debootstrap`
# version not knowing about newer OS releases, so manual creation should rarely
# be necessary.
#
# 2. Make the rootfs chroot-able
#
# To be chroot-able (and friendly to `apt`), the netboot root filesystem needs
# to have `/proc`, `/sys`, and `/dev/pts` mounted in the netboot root filesystem
# tree.  If `/proc` is already mounted in the netboot root filesystem, then this
# script will assume that all of these mounts have been already configured.  If
# `/proc` is NOT mounted in the netboot root filesystem, this script will modify
# `/etc/fstab` to include lines that specify how to mount `/proc`, `/sys`,
# and `/dev/pts`, as well as a tmpfs mount on `/tmp` and bind mount of `/homa`
# in the netboot root filesystem tree and then mount them.  The existing
# `/etc/fstab` is backed up to `/etc/fstab.netbootstrap.YYYYmmddHHMMSS`, where
# `YYYYmmddHHMMSS` is the time of the backup, before any modifications are
# made.
#
# This step also copies a utility script `nbroot` to `/usr/local/sbin` on the
# head node.  This script is a convenience wrapper around `chroot` to simplify
# `chroot`-ing to netboot root filesystems.
#
# 3. chroot into rootfs and install additional packages (and remove some).
#
# This beefs up the netboot rootfs with more packages and removes some
# conventional boot related packages that we don't want/need for netboot.  This
# step also removes the `/etc/hostname` file from the netboot rootfs.  This step
# will be skipped if it looks like it has already been done.
#
# 4. Add some netboot-specific `tmpfiles.d` files to rootfs `/etc/tmpfiles.d`.
#
# All the netboot clients NFS mount the same rootfs as read-only.  Some daemons
# expect to be able to write state information to `/var`, which it part of the
# read-only root file system.  To facilitate this, the netboot nodes also NFS
# mount a host-specific directory from the head node as read-write.  To create
# the requisite subdirectories and symlinks, files provided in
# [`netboot_root_files/etc/tmpfiles.d`](../netboof_root_files/etc/tmpfiles.d)
# are copied to the `/etc/tmpfiles.d` directory of rootfs.  See the comments in
# [`netboot-base.conf`](../netboof_root_files/etc/tmpfiles.d/netboot-base.conf)
# for more details.
#
# 5. Run `systemd-tmpfiles --create` in the rootfs for the new `tmpfiles.d`
#    files.
#
# The symlinks in the rootfs cannot be created by the netboot clients because
# they mount rootfs as read-only, so the symlinks must be pre-created on the
# head node by `chroot`-ing into rootfs and running `systemd-tmpfiles --create`.
#
# 6. Setup `initramfs-tools` in rootfs and run `update-initramfs`.
#
# The initramfs filesystem performs early initializtion of a booting system.
# The `initramfs-tools` package provides a convenient way to add various
# customizations to this process.  In addition to a netboot specific
# [`initramfs.conf`](../netboot_root_files/etc/initramfs-tools/initramfs.conf)
# file, an additional script is included to mount the host-specific read-write
# persistent filesystem as early as possible.
#
# 7. Setup `/etc/fstab` file in rootfs.
#
# The `/etc/fstab` file of the rootfs is configured to include the NFS root
# directory and the `/home` directory.  Entries are also created for `tmpfs`
# filesystems `/tmp` and `/var/lib/sudo`.  The file is not modified if it looks
# like it has already been configured.
#
# 8. Install a few packages on the head node (that may already be installed):
#
# The following packages are required on the # head node for netbooting.
#
#    - nfs-kernel-server
#    - syslinux-common
#    - pxelinux
#
# 9. Setup `/etc/exports` to export the rootfs and persistentfs
#
# The `/etc/exports` file on the current host is modified to export the netboot
# rootfs and persistentfs (the parent directory that will contain the host
# specific persistent filesystems) and `/home` over the `NFS_SUBNET` subnet.
# The existing `/etc/exports` file will be backed up prior to modification in a
# manner similar to `/etc/fstab`.  This step also creates the parent directory
# for the host-specific persistent directories.
#
# 10. Copy some files to a tftpboot directory on the head node
#
# The PXE boot process uses TFTP to transfer boot related files to the netboot
# clients.  These files are copied or symlinked to a common directory that
# defaults to `/srv/tftpboot`, but can be overidden by exporting the
# `TFTPBOOT_DIR` environemt variable before running this script.
#
# At this point all that remains to be done is to setup the DHCP server to pass
# the proper options to PXE clients and to setup the PXE config to present to
# proper options in the PXE boot menu.  These last few steps are rather
# dependent on the specifics of the head node (e.g. which DHCP server is being
# used, which TFTP server is being used, which DNS server is being used, etc.)
# so they are not performed by this script.  Other resources to support those
# steps will be developed and included in this repository.  Stay tuned!


# The variables here allow for some level of customization by hacking this
# script.  Maybe one day we'll have proper command line argument parsing.
# For now, setting the `CODENAME`, `ARCH`, `SRV_ROOT`, and `TFTPBOOT_DIR`
# environment variables before calling this script will override the defaults
# set here.

# Which release (by codename) and architecture to target
CODENAME="${CODENAME:-noble}"
ARCH="${ARCH:-$(dpkg --print-architecture 2>/dev/null || echo 'amd64')}"

# Where to install various netboot components
SRV_ROOT="${SRV_ROOT:-/srv}"

# Where to install files for TFTP
TFTPBOOT_DIR="${TFTPBOOT_DIR:-${SRV_ROOT}/tftpboot}"

# Which version of debootstrap to download
DEBOOTSTRAP_VERSION="${DEBOOTSTRAP_VERSION:-1.0.134ubuntu1_all}" # Ubuntu 24.04
# Where to download debootstrap package from
DEBOOTSTRAP_URL="${DEBOOTSTRAP_URL:-http://mirrors.kernel.org/ubuntu/pool/main/d/debootstrap/debootstrap_${DEBOOTSTRAP_VERSION}.deb}"

# The variables below here are not typically overridden

NETBOOT_ROOT="${SRV_ROOT}/${CODENAME}/rootfs.${ARCH}"
PERSISTENT_ROOT="${SRV_ROOT}/${CODENAME}/persistent"
# Use exsiting value of TFTPBOOT_DIR, if any

# Options for NFS exports
EXPORT_OPTS="rw,no_root_squash,no_subtree_check"

# Where to find resource files for netboot root filesystem
NBROOT_FILES="$(dirname $0)/../netboot_root_files"

# Generate timestamp for various uses (e.g. names of backup files)
TS="$(date +%Y%m%d%H%M%S)"

# Change to other filename when testing fstab and exports updates
FSTAB=/etc/fstab
EXPORTS=/etc/exports

# 0. Check command line

if [ -z "$2" ]
then
    echo "usage: $(basename $0) NFS_SERVER_IP NFS_SUBNET"
    exit 1
fi

NFS_SERVER="$1"
NFS_SUBNET="$2"

# 1. Use `debootstrap` to create a minimalistic root filesystem

# Run debootstrap (or not)
if ! [ -e "${NETBOOT_ROOT}" ]
then
    # Ensure that zstd is available (required by recent debootstrap versions)
    if ! dpkg -l zstd >& /dev/null
    then
        echo "${NETBOOT_ROOT} does not exist " \
             "but zstd package is not installed, cannot continue"
        exit 1
    fi

    echo "${NETBOOT_ROOT} does not exist, debootstrap ${CODENAME} into ${NETBOOT_ROOT}"

    # Run in a sub-shell to avoid needing to cd back
    (
        # Mount a new tmpfs file system to avoid any `noexec` flag on /tmp
        mkdir -p "${TMPDIR:-/tmp}/debootstrap.$$"
        mount -t tmpfs tmpfs "${TMPDIR:-/tmp}/debootstrap.$$"
        cd "${TMPDIR:-/tmp}/debootstrap.$$"

        # Download and extract debootstrap .deb file
        wget -O debootstrap.deb "${DEBOOTSTRAP_URL}"
        dpkg -x debootstrap.deb debootstrap

        # Add modern ubuntu key to apt
        apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 \
                    --recv-keys 871920D1991BC93C

        # Run debootstrap
        env DEBOOTSTRAP_DIR=`pwd`/debootstrap/usr/share/debootstrap \
            ./debootstrap/usr/sbin/debootstrap \
            --keyring=/etc/apt/trusted.gpg --variant=buildd \
            ${CODENAME} ${NETBOOT_ROOT} http://archive.ubuntu.com/ubuntu

        # Clean up
        cd "${TMPDIR:-/tmp}"
        umount debootstrap.$$
    )
else
    echo "${NETBOOT_ROOT} exists, skipping debootstrap step"
fi

# 2. Make the rootfs chroot-able

# Modify /etc/fstab and mount (or not)
if grep -q "${NETBOOT_ROOT}/proc" /proc/mounts
then
    echo "${NETBOOT_ROOT}/proc is mounted, skipping ${FSTAB} modifications and mounts"
else
    echo "${NETBOOT_ROOT}/proc is not mounted, modifying ${FSTAB} and mounting"

    # Backup /etc/fstab
    echo "backing up ${FSTAB} to ${FSTAB}.netbootstrap.${TS}"
    cp "${FSTAB}" "${FSTAB}.netbootstrap.${TS}"

    echo "modifying ${FSTAB} to make ${NETBOOT_ROOT} chroot-able"

    # Remove all lines containing ${NETBOOT_ROOT} from /etc/fstab
    sed -i "\\:${NETBOOT_ROOT}:d" "${FSTAB}"

    # Add lines to /etc/fstab to mount /proc, /sys, and /dev/pts
    cat >> ${FSTAB} << EOF
# Mounts to make ${NETBOOT_ROOT} chroot-able
proc    ${NETBOOT_ROOT}/proc     proc    defaults 0 0
sysfs   ${NETBOOT_ROOT}/sys      sysfs   defaults 0 0
tmpfs   ${NETBOOT_ROOT}/tmp      tmpfs   defaults 0 0
devpts  ${NETBOOT_ROOT}/dev/pts  devpts  defaults 0 0
# Bind mount /home to ${NETBOOT_ROOT}/home
/home   ${NETBOOT_ROOT}/home     none    bind     0 0
EOF

    # If modifying /etc/fstab, mount /proc, /sys, /tmp, and /dev/pts in netboot
    # root
    if [ "${FSTAB}" = /etc/fstab ]
    then
        for d in proc sys tmp dev/pts
        do
            echo "mounting ${NETBOOT_ROOT}/$d"
            mount "${NETBOOT_ROOT}/$d"
        done
    else
        echo "${FSTAB} is not /etc/fstab, skipping mounts"
    fi
fi

# Copy nbroot to head node /usr/local/sbin
cp -u "${NBROOT_FILES}/usr/local/sbin/nbroot" "/usr/local/sbin/."

# 3. `chroot` into rootfs and install additional packages (and remove some).

if [ -e "${NETBOOT_ROOT}/usr/bin/tree" ]
then
    echo "not installling additional packages, ${NETBOOT_ROOT} appears to have them already"
else
    echo "installing additional packages"
    # Use chroot to add additional packages and remove unwanted ones
    set -x
    chroot "${NETBOOT_ROOT}" apt update
    chroot "${NETBOOT_ROOT}" apt install -y 'server^' --no-install-recommends
    chroot "${NETBOOT_ROOT}" add-apt-repository -y universe
    chroot "${NETBOOT_ROOT}" apt update
    chroot "${NETBOOT_ROOT}" apt install -y 'standard^'
    #chroot "${NETBOOT_ROOT}" dpkg-reconfigure debconf
    #--- choose “Dialog” and "high" ---
    # === Install additional packages (if not already installed) ===
    chroot "${NETBOOT_ROOT}" apt install -y 'server-minimal^' 'openssh-server^' linux-generic nfs-common --no-install-recommends
    chroot "${NETBOOT_ROOT}" apt install -y apt-utils less networkd-dispatcher tree iputils-ping fping
    # === Remove unwanted packages ===
    chroot "${NETBOOT_ROOT}" apt remove -y --purge snapd unattended-upgrades apparmor plymouth
    chroot "${NETBOOT_ROOT}" apt remove -y --purge --autoremove landscape-common ubuntu-release-upgrader-core update-notifier-common
    chroot "${NETBOOT_ROOT}" rm -rf /var/lib/update-notifier /etc/hostname
    set +x

    # Set the SUID sticky bit on ping and fping since they run from NFS mount
    chmod 4755 /bin/ping /usr/bin/fping
fi

# 4. Add `defatul` and `tmpfiles.d` files to rootfs `/etc/default` and
# `/etc/tmpfiles.d`.

for d in default tmpfiles.d
do
    echo "copying files from ${NBROOT_FILES}/etc/$d to ${NETBOOT_ROOT}/etc"
    cp -rv "${NBROOT_FILES}/etc/$d" "${NETBOOT_ROOT}/etc"
done

# 5. Run `systemd-tmpfiles --create` in the rootfs for the new `tmpfiles.d`
#    files.

conffiles=$(chroot "${NETBOOT_ROOT}" bash -c 'ls /etc/tmpfiles.d/netboot*.conf')
for c in $conffiles
do
    echo "running 'systemd-tmpfiles --create $c' in ${NETBOOT_ROOT}"
    chroot "${NETBOOT_ROOT}" systemd-tmpfiles --create $c
done

# 6. Setup `initramfs-tools` in rootfs and run `update-initramfs`.

echo "copying files from ${NBROOT_FILES}/etc/initramfs-tools to ${NETBOOT_ROOT}/etc"
cp -rv "${NBROOT_FILES}/etc/initramfs-tools" "${NETBOOT_ROOT}/etc"

echo "running 'update-initramfs -u' in ${NETBOOT_ROOT}"
chroot "${NETBOOT_ROOT}" update-initramfs -u

# 7. Setup `/etc/fstab` file in rootfs.

NETBOOT_FSTAB="${NETBOOT_ROOT}/etc/fstab"
# If file does not exist or it contains UNCONFIGURED text, create/modify it
if [ ! -e "${NETBOOT_FSTAB}" ] || grep -q "# UNCONFIGURED FSTAB FOR BASE SYSTEM" "${NETBOOT_FSTAB}" 2>/dev/null
then
    echo "setting up ${NETBOOT_ROOT}/etc/fstab"

    padding="$(echo -n ${NETBOOT_ROOT} | sed 's/./ /g')"
    cat > "${NETBOOT_FSTAB}" <<EOF
# NFS mounts
${NFS_SERVER}:${NETBOOT_ROOT}  /      nfs  ro,hard,nointr,nfsvers=3  0  0
${NFS_SERVER}:/home${padding:5}  /home  nfs  rw,hard,nointr,nfsvers=3  0  0

# tmpfs filesystems
none  /tmp           tmpfs  mode=1777,rw,nosuid,nodev,noexec  0  0
none  /var/lib/sudo  tmpfs  mode=0700,rw,nosuid,nodev,noexec  0  0
EOF
else
    echo "${NETBOOT_ROOT}/etc/fstab appears to be setup already"
fi

# 8. Install a few packages on the head node (that may already be installed):
#
#    - nfs-kernel-server
#    - syslinux-common
#    - pxelinux

echo "installing packages: nfs-kernel-server syslinux-common pxelinux"
apt install -y nfs-kernel-server syslinux-common pxelinux

# 9. Setup `/etc/exports` to export the rootfs and persistentfs

if [ -d "${PERSISTENT_ROOT}" ]
then
    echo "${PERSISTENT_ROOT} already exists"
else
    echo "creating ${PERSISTENT_ROOT}"
    mkdir -p "${PERSISTENT_ROOT}"
fi

# Backup /etc/exports
echo "backing up ${EXPORTS} to ${EXPORTS}.netbootstrap.${TS}"
cp "${EXPORTS}" "${EXPORTS}.netbootstrap.${TS}"

echo "modifying ${EXPORTS}"

# Remove all lines exporting rootfs, persistentfs, and /home to NFS_SUBNET
for d in "${NETBOOT_ROOT}" "${PERSISTENT_ROOT}" /home
do
    sed -i "\\:^${d}\s\+${NFS_SUBNET}(:d" "${EXPORTS}"
done

# Add lines to export rootfs, persistentfs, /home to NFS_SUBNET
n1="$(echo ${NETBOOT_ROOT} | wc -c)"
n2="$(echo ${PERSISTENT_ROOT} | wc -c)"
n=$((n1>n2 ? n1 : n2))
for d in "${NETBOOT_ROOT}" "${PERSISTENT_ROOT}" /home
do
    printf "%-${n}s %s\\n" "${d}" "${NFS_SUBNET}(${EXPORT_OPTS})" >> "${EXPORTS}"
done

# If modifying /etc/fstab (i.e. not testing), export the directories
if [ "${EXPORTS}" = /etc/exports ]
then
    # Export directories to NFS_SUBNET
    for d in "${NETBOOT_ROOT}" "${PERSISTENT_ROOT}" /home
    do
        echo "exporting ${d} to ${NFS_SUBNET}"
        exportfs "${NFS_SUBNET}:${d}"
    done
fi

# 10. Copy some files to a "tftp boot" directory on the head node

pxedir="${TFTPBOOT_DIR}/pxe"
codenamedir="${pxedir}/${CODENAME}"

if [ -d "${codenamedir}" ]
then
    echo "${codenamedir} already exists"
else
    echo "creating ${codenamedir}"
    mkdir -p "${codenamedir}"
fi

echo "copying PXE files to ${pxedir}"
for f in /usr/lib/PXELINUX/pxelinux.0 \
         /usr/lib/syslinux/modules/bios/ldlinux.c32 \
         /usr/lib/syslinux/modules/bios/libutil.c32 \
         /usr/lib/syslinux/modules/bios/menu.c32
do
    cp -uv "${f}" "${pxedir}"
done

echo "symlinking kernel and initrd files to ${codenamedir}"
for f in vmlinuz initrd.img
do
    if [ -e "${codenamedir}/${f}" ]
    then
        echo "${codenamedir}/${f} already exists"
    else
        ln -sv "${NETBOOT_ROOT}/boot/${f}" "${codenamedir}/${f}"
    fi
done

# Make kernels world readable
chmod a+r "${NETBOOT_ROOT}"/boot/vmlinuz-*

# Make PXE menu entries file
menufile="${codenamedir}/pxelinux.menu"

if [ -e "${menufile}" ]
then
    echo "${menufile} already exists"
else
    echo "creating ${menufile}"

    prettyname="$(sed -n '/PRETTY_NAME=/{s/^.*=//;s/"//g;p}' "${NETBOOT_ROOT}/etc/os-release")"
    cat > "${menufile}" <<EOF
LABEL ${CODENAME}
    MENU LABEL ${prettyname}
    KERNEL ${CODENAME}/vmlinuz
    APPEND initrd=${CODENAME}/initrd.img root=/dev/nfs nfsroot=${NFS_SERVER}:${NETBOOT_ROOT} blacklist=nouveau nouveau.modeset=0 console=tty0 console=ttyS1,115200 ro
    IPAPPEND 2

LABEL ${CODENAME}overlayroot
    MENU LABEL ${prettyname} (w/ overlayroot)
    KERNEL ${CODENAME}/vmlinuz
    APPEND initrd=${CODENAME}/initrd.img root=/dev/nfs nfsroot=${NFS_SERVER}:${NETBOOT_ROOT} blacklist=nouveau nouveau.modeset=0 console=tty0 console=ttyS1,115200 ro overlayroot=tmpfs
    IPAPPEND 2
EOF
fi

# Make sample PXE "default" file for CODENAME
defaultfile="${pxedir}/pxelinux.cfg/default.${CODENAME}"

if [ -e "${defaultfile}" ]
then
    echo "${defaultfile} already exists"
else
    echo "creating ${defaultfile}"

    mkdir -p "$(dirname "${defaultfile}")"

    prettyname="$(sed -n '/PRETTY_NAME=/{s/^.*=//;s/"//g;p}' "${NETBOOT_ROOT}/etc/os-release")"
    cat > "${defaultfile}" <<EOF
UI menu.c32
MENU TITLE ${NETBOOT_ORGNAME:-Super Amazing} PXE Boot Menu

# Wait 5 seconds unless the user types something, but
# always boot after 5 minutes
TIMEOUT 50
TOTALTIMEOUT 3000

# Set default boot image. Without DEFAULT the first LABEL in the file
# is chosen as the default
DEFAULT ${CODENAME}

INCLUDE ${CODENAME}/pxelinux.menu

MENU SEPARATOR

LABEL reload
    MENU LABEL Reload this menu
    KERNEL menu.c32
EOF
fi
