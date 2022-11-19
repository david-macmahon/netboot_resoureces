#!/bin/bash

# # netbootstrap.sh
#
# ## Overview
#
# Make a netbooot-able Ubuntu root file system directory.  This involves the
# following steps:
#
# 1. Use debootstrap to create a minimalistic root filesystem (rootfs)
#
# 2. Make the rootfs chroot-able
#    2.1 Add entries to /etc/fstab to mount /proc, /sys, /dev/pts in rootfs
#    2.2 Mount /proc, /sys, and /dev/pts in the rootfs
#
# 3. chroot into rootfs and install addition packages (and remove some).
#
# 4. Add some tmpfiles.d files to rootfs /etc/tmpfiles.d.
#
# 5. Run systemd-tmpfiles --create in the rootfs for the new tmpfile.f files.
#
# 6. Setup initramfs-tools in rootfs and run update-initramfs.
#
# 7. Setup /etc/fstab file in rootfs.
#
# At this point rootfs is technically net bootable, but in order for clients to
# actually netboot it some additional configuration is required on the head
# node.
#
# 8. Install a few packages on the head node (that may already be installed):
#    - nfs-kernel-server
#    - syslinux-common
#    - pxelinux
#
# 9. Setup /etc/exports to export the rootfs and persistentfs
#
# 10. Copy some files to a tftpboot directory on the head node
#
# ## Details
#
# Here are more details about the steps mentioned in the overview above.
#
# 1. Use debootstrap to create a minimalistic root filesystem (rootfs)
#
# This will run `debootstrap` to create the base root filesystem if the
# destination does not exist.  If the destination does exist, then it will skip
# the debootstrap step and assume that it was already initialized
# appropriately.  This is to support the manual creation of netboot root
# filesystems for releases that are newer than the host OS's debootstrap
# program will natively support (i.e. Ubuntu 16.04 cannot debootstrap an Ubuntu
# 22.04 "jammy" root file system).
#
# 2. Make the rootfs chroot-able
#
# To be chroot-able, the netboot root filesystem needs to have /proc, /sys,
# and /dev/pts mounted in the netboot root filesystem tree.  If /proc is
# already mounted in the netboot root filesystem, then this script will assume
# that all of these mounts have been already configured.  If /proc is NOT
# mounted in the netboot root filesystem, this script will modify /etc/fstab
# to include lines that specify how to mount /proc, /sys and /dev/pts in the
# netboot root filesystem tree and then mount them.  The existing /etc/fstab is
# backed up to /etc/fstab.netbootstrap.YYYYmmddHHMMSS, where YYYYmmddHHMMSS is
# the time of the backup, before any modifications are made.
#
# 3. chroot into rootfs and install additional packages (and remove some).
#
# 4. Add some tmpfiles.d files to rootfs /etc/tmpfiles.d.
#
# 5. Run systemd-tmpfiles --create in the rootfs for the new tmpfile.f files.
#
# 6. Setup initramfs-tools in rootfs and run update-initramfs.
#
# 7. Setup /etc/fstab file in rootfs.
#
# 8. Install a few packages on the head node (that may already be installed):
#    - nfs-kernel-server
#    - syslinux-common
#    - pxelinux
#
# 9. Setup /etc/exports to export the rootfs and persistentfs
#
# 10. Copy some files to a tftpboot directory on the head node
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

# Which release (by codename) and architecture to target
CODENAME=jammy
ARCH=amd64

# Where to install various netboot components
SRV_ROOT=/srv
NETBOOT_ROOT="${SRV_ROOT}/${CODENAME}/rootfs.${ARCH}"
PERSISTENT_ROOT="${SRV_ROOT}/${CODENAME}/persistent"
TFTPBOOT_ROOT="${SRV_ROOT}/tftproot"

# Generate timestamp for various uses (e.g. names of backup files)
TS="$(date +%Y$m$d%H%M%S)"

# Change to other filename when testing fstab updates
FSTAB=/etc/fstab

# Run debootstrap (or not)
if ! [ -e "${NETBOOT_ROOT}" ]
then
    echo "${NETBOOT_ROOT} does not exist, debootstrap ${CODENAME} into ${NETBOOT_ROOT}"
    debootstrap --variant=buildd ${CODENAME} ${NETBOOT_ROOT} http://archive.ubuntu.com/ubuntu
else
    echo "${NETBOOT_ROOT} exists, skipping debootstrap step"
fi

# Modify /etc/fstab and mount (or not)
if grep -q "${NETBOOT_ROOT}/proc" /proc/mounts
then
    echo "${NETBOOT_ROOT}/proc is mounted, skipping ${FSTAB} modifications and mounts"
else
    echo "${NETBOOT_ROOT}/proc is not mounted, modifying ${FSTAB} and mounting"

    # Backup /etc/fstab
    echo "backing up ${FSTAB} to ${FSTAB}.${TS}"
    cp "${FSTAB}" "${FSTAB}.${TS}"

    echo "modifying ${FSTAB} to make ${NETBOOT_ROOT} chroot-able"

    # Remove all lines containing ${NETBOOT_ROOT} from /etc/fstab
    sed -i "\\:${NETBOOT_ROOT}:d" "${FSTAB}"

    # Add lines to /etc/fstab to mount /proc, /sys, and /dev/pts
    cat >> ${FSTAB} << EOF
# Mounts to make ${NETBOOT_ROOT} chroot-able
proc    ${NETBOOT_ROOT}/proc     proc    defaults 0 0
sysfs   ${NETBOOT_ROOT}/sys      sysfs   defaults 0 0
devpts  ${NETBOOT_ROOT}/dev/pts  devpts  defaults 0 0
# Bind mount ${NETBOOT_ROOT}/home if desired, but not strictly needed
#/home   ${NETBOOT_ROOT}/home     none    bind     0 0
EOF

    # If modifying /etc/fstab, mount /proc, /sy, and /dev/pts in netboot root
    if [ "${FSTAB}" = /etc/fstab ]
    then
        for d in proc sys dev/pts
        do
            echo "mounting ${NETBOOT_ROOT}/$d"
            mount "${NETBOOT_ROOT}/$d"
        done
    else
        echo "${FSTAB} is not /etc/fstab, skipping mounts"
    fi
fi

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
chroot "${NETBOOT_ROOT}" apt install -y ansible apt-utils less tree
# === Remove unwanted packages ===
chroot "${NETBOOT_ROOT}" apt remove -y --purge snapd unattended-upgrades apparmor plymouth
chroot "${NETBOOT_ROOT}" apt remove -y --purge --autoremove landscape-common ubuntu-release-upgrader-core update-notifier-common
chroot "${NETBOOT_ROOT}" rm -rf /var/lib/update-notifier /etc/hostname
set +x
