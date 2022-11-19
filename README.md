# Netboot Resources

A collection of files that are useful for setting up an Ubuntu netboot root
filesystem.  The main functionality is provided by the script
[`netbootstrap.sh`](bootstrap/netbootstrap.dh).


## netbootstrap.sh

Make a netbooot-able Ubuntu root file system directory.  This involves the
following steps (currently implemented only through step 3):

### Build the root filesystem

1. Use debootstrap to create a minimalistic root filesystem (rootfs)

2. Make the rootfs chroot-able

   2.1 Add entries to /etc/fstab to mount /proc, /sys, /dev/pts in rootfs

   2.2 Mount /proc, /sys, and /dev/pts in the rootfs

3. chroot into rootfs and install addition packages (and remove some).

4. Add some tmpfiles.d files to rootfs /etc/tmpfiles.d.

5. Run systemd-tmpfiles --create in the rootfs for the new tmpfile.f files.

6. Setup initramfs-tools in rootfs and run update-initramfs.

7. Setup /etc/fstab file in rootfs.

### Setup the head node

At this point rootfs is technically netbootable, but in order for clients to
actually netboot it some additional configuration is required on the head
node.

8. Install a few packages on the head node (that may already be installed):
   - nfs-kernel-server
   - syslinux-common
   - pxelinux

9. Setup /etc/exports to export the rootfs and persistentfs

10. Copy some files to a tftpboot directory on the head node

### Almost there!

The last few steps of stitching together the DHCP server, TFTP server, and PXE
boot menu on the head node are heavily dependent on the local configuration.
Additional resources to support these remaining few tasks will be developed and
included in this repository.

Stay tuned!
