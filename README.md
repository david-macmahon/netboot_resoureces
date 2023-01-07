# Netboot Resources

A collection of files that are useful for setting up an Ubuntu netboot root
filesystem.  The main functionality is provided by the script
[`netbootstrap.sh`](bootstrap/netbootstrap.dh).

## netbootstrap.sh

Make a netbooot-able Ubuntu root file system directory.

### Usage

```
netbootstrap.sh NFS_SERVER_IP NFS_SUBNET

NFS_SERVER_IP is the IP address on the current host that netboot clients will
use to mount the netboot root filesystem (and others).  This value is used
when creating /etc/fstab in the netboot root filesystem.

NFS_SUBNET is the subnet over which the netboot root filesystem (and others)
will be NFS exported.  This value is is used when modifying /etc/exports on
the netboot NFS server.

Example: netbootstrap.sh 10.0.1.1 10.0.1.0/24
```

The bootstrap process can be customized by setting these environment variables,
shown here with their default values, before running `netbootstrap.sh`:

- Which release (by codename) and architecture to target.  Technically, `ARCH`
  defaults to `$(dpkg --print-architecture)`, but if that command fails then
  the default of `amd64` is used.

  ```sh
  CODENAME="jammy"
  ARCH="amd64"
  ```

- Where to install various netboot components

  ```sh
  SRV_ROOT="/srv"
  ```

- Where to install files for TFTP

  ```sh
  TFTPBOOT_DIR="${SRV_ROOT}/tftpboot"
  ```

### What it does

The `netbootstrap.sh` script performs two main function:

- Build the root filesystem
- Configure the head node

The last few steps of stitching together the DHCP server, TFTP server, and PXE
boot menu on the head node are heavily dependent on the local configuration.
Additional resources to support these remaining few tasks will be developed and
included in this repository.  Stay tuned!

Read on for details of what the script does.

#### Build the root filesystem

1. Use `debootstrap` to create a minimalistic root filesystem (rootfs)

   This will run `debootstrap` to create the base root filesystem if the
   destination does not exist.  If the destination does exist, then it will skip
   the `debootstrap` step and assume that it was already initialized
   appropriately.  This is to support the manual creation of netboot root
   filesystems for releases that are newer than the host OS's debootstrap
   program will natively support.  For examples, Ubuntu 16.04 cannot
   `debootstrap` an Ubuntu 22.04 "jammy" root file system so it must be
   pre-created externally, e.g. by manually using `debootstrap` to create a new
   enonugh root filesystem that can `debootstrap` "jammy".

2. Make the rootfs chroot-able

   To be chroot-able (and friendly to `apt`), the netboot root filesystem needs
   to have `/proc`, `/sys`, and `/dev/pts` mounted in the netboot root
   filesystem tree.  If `/proc` is already mounted in the netboot root
   filesystem, then this script will assume that all of these mounts have been
   already configured.  If `/proc` is NOT mounted in the netboot root
   filesystem, this script will modify `/etc/fstab` to include lines that
   specify how to mount `/proc`, `/sys` and `/dev/pts` in the netboot root
   filesystem tree and then mount them.  The existing `/etc/fstab` is backed up
   to `/etc/fstab.netbootstrap.YYYYmmddHHMMSS`, where `YYYYmmddHHMMSS` is the
   time of the backup, before any modifications are made.

3. chroot into rootfs and install additional packages (and remove some).

   This beefs up the netboot rootfs with more packages and removes some
   conventional boot related packages that we don't want/need for netboot.  This
   step also removes the `/etc/hostname` file from the netboot rootfs.  This
   step will be skipped if it looks like it has already been done.

4. Add some netboot-specific `tmpfiles.d` files to rootfs `/etc/tmpfiles.d`.

   All the netboot clients NFS mount the same rootfs as read-only.  Some daemons
   expect to be able to write state information to `/var`, which it part of the
   read-only root file system.  To facilitate this, the netboot nodes also NFS
   mount a host-specific directory from the head node as read-write.  To create
   the requisite subdirectories and symlinks, files provided in
   [`netboot_root_files/etc/tmpfiles.d`](../netboof_root_files/etc/tmpfiles.d)
   are copied to the `/etc/tmpfiles.d` directory of rootfs.  See the comments in
   [`netboot-base.conf`](../netboof_root_files/etc/tmpfiles.d/netboot-base.conf)
   for more details.

5. Run `systemd-tmpfiles --create` in the rootfs for the new `tmpfiles.d`
   files.

   The symlinks in the rootfs cannot be created by the netboot clients because
   they mount rootfs as read-only, so the symlinks must be pre-created on the
   head node by `chroot`-ing into rootfs and running `systemd-tmpfiles
   --create`.

6. Setup `initramfs-tools` in rootfs and run `update-initramfs`.

   The initramfs filesystem performs early initializtion of a booting system.
   The `initramfs-tools` package provides a convenient way to add various
   customizations to this process.  In addition to a netboot specific
   [`initramfs.conf`](../netboot_root_files/etc/initramfs-tools/initramfs.conf)
   file, an additional script is included to mount the host-specific read-write
   persistent filesystem as early as possible.

7. Setup `/etc/fstab` file in rootfs.

   The `/etc/fstab` file of the rootfs is configured to include the NFS root
   directory and the `/home` directory.  Entries are also created for `tmpfs`
   filesystems `/tmp` and `/var/lib/sudo`.  The file is not modified if it looks
   like it has already been configured.

#### Setup the head node

At this point rootfs is technically netbootable, but in order for clients to
actually netboot it some additional configuration is required on the head
node.


8. Install a few packages on the head node (that may already be installed):

   The following packages are required on the head node for netbooting.

   - nfs-kernel-server
   - syslinux-common
   - pxelinux

9. Setup `/etc/exports` to export the rootfs and persistentfs

   The `/etc/exports` file on the current host is modified to export the netboot
   rootfs and persistentfs (the parent directory that will contain the host
   specific persistent filesystems) and `/home` over the `NFS_SUBNET` subnet.
   The existing `/etc/exports` file will be backed up prior to modification in a
   manner similar to `/etc/fstab`.  This step also creates the parent directory
   for the host-specific persistent directories.

10. Copy some files to a tftpboot directory on the head node

    The PXE boot process uses TFTP to transfer boot related files to the netboot
    clients.  These files are copied or symlinked to a common directory that
    defaults to `/srv/tftpboot`, but can be overidden by exporting the
    `TFTPBOOT_DIR` environemt variable before running this script.

## Next steps

A few essential steps are remain to be done at this point:

- Finalize the configuration of the PXE boot menu.

  This could be as simple as renaming (or symlinking) the sample PXE
  configuration file created in the last step to `default`.

- Finalize the configuration of the DHCP and TFTP servers to support PXE boot.

  This step depends on which programs are being used to provide these services.

- Create per-host subdirectories in persistentfs.

  This will be handled by an ansible playbook, but for now you must manually
  create these subdirectories.

- Setup users in the netboot root

  The recommended approach is to run LDAP on the head node and configure the
  netboot systems to authenticate users against the LDAP database on the head
  node.  Ansible playbooks will be developed for this.

  If you wish to avoid LDAP, you may want to simply copy the non-system
  users/groups from the head node's `/etc` files to the netboot's `/etc` files.
  Note that the UIDs and GIDs of system users and groups may differ between head
  node and netboot nodes, so copying those is strongly discouraged.  If you go
  this way, don't forget to copy the correspinding entries is `/etc/shadow` and
  `/etc/gshadow`.

- Install additional drivers on the netboot nodes (e.g. GPU drivers, NIC
  drivers, etc.)
- Configure additional network interfaces on the netboot nodes.

  These are getting somewhat outside the scope of establishing a viable netboot
  system, but reseources for some additional sysadmin tasks like these will also
  be made available here.
