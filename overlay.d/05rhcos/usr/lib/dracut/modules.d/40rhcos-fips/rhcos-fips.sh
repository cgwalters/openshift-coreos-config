#!/bin/bash
set -euo pipefail

IGNITION_CONFIG=/run/ignition.json
# https://github.com/openshift/machine-config-operator/pull/868
MACHINE_CONFIG_ENCAPSULATED=/etc/ignition-machine-config-encapsulated.json

main() {
    mode=$1; shift
    case "$mode" in
        firstboot) firstboot;;
        finish) finish;;
        *) fatal "Invalid mode $mode";;
    esac
}

firstboot() {
    if [ "$(</proc/sys/crypto/fips_enabled)" -eq 1 ]; then
        noop "FIPS mode is enabled."
    fi

    if [ ! -f "${IGNITION_CONFIG}" ]; then
        fatal "Missing ${IGNITION_CONFIG}"
    fi

    local tmp=/run/rhcos-fips
    local tmpsysroot="${tmp}/sysroot"
    coreos-dummy-ignition-files-run "${tmp}" "${IGNITION_CONFIG}" "${MACHINE_CONFIG_ENCAPSULATED}"

    if [ ! -f "${tmpsysroot}/${MACHINE_CONFIG_ENCAPSULATED}" ]; then
        noop "No ${MACHINE_CONFIG_ENCAPSULATED} found in Ignition config"
    fi

    echo "Found ${MACHINE_CONFIG_ENCAPSULATED} in Ignition config"

    # don't use -e here to distinguish between false/null
    case $(jq .spec.fips "${tmpsysroot}/${MACHINE_CONFIG_ENCAPSULATED}") in
        false) noop "FIPS mode not requested";;
        true) ;;
        *)
            cat "${tmpsysroot}/${MACHINE_CONFIG_ENCAPSULATED}"
            fatal "Missing/malformed FIPS field"
            ;;
    esac

    echo "FIPS mode required; updating BLS entries"

    mkdir -p "${tmpsysroot}/boot"
    mount /dev/disk/by-label/boot "${tmpsysroot}/boot"

    for f in "${tmpsysroot}"/boot/loader/entries/*.conf; do
        echo "Appending 'fips=1 boot=LABEL=boot' to ${f}"
        sed -e "/^options / s/$/ fips=1 boot=LABEL=boot/" -i "$f"
    done
    sync -f "${tmpsysroot}/boot"

    if [[ $(uname -m) = s390x ]]; then
      # Similar to https://github.com/coreos/coreos-assembler/commit/100c2e512ecb89786a53bfb1c81abc003776090d in the coreos-assembler
      # We need to call zipl with the kernel image and ramdisk as running it without these options would require a zipl.conf and chroot
      # into rootfs
      tmpfile=$(mktemp)
      for f in "${tmpsysroot}"/boot/loader/entries/*.conf; do
          for line in title version linux initrd options; do
              echo $(grep $line $f) >> $tmpfile
          done
      done
      zipl --verbose \
           --target "${tmpsysroot}/boot" \
           --image $tmpsysroot/boot/"$(grep linux $tmpfile | cut -d' ' -f2)" \
           --ramdisk $tmpsysroot/boot/"$(grep initrd $tmpfile | cut -d' ' -f2)" \
           --parmfile $tmpfile
    fi

    echo "Rebooting"
    systemctl --force reboot
}

finish() {
    # This is analogous to Anaconda's `chroot /sysroot fips-mode-setup`. Though
    # of course, since our approach is "Ignition replaces Anaconda", we have to
    # do it on firstboot ourselves. The key part here is that we do this
    # *before* the initial switch root.

    # We need to teach `fips-mode-setup` about OSTree systems. E.g. it wants to
    # query and rebuild the initrd. For now, just do the tiny subset of what we
    # need it to do.
    sysroot_bwrap update-crypto-policies --set FIPS --no-reload
    echo '# RHCOS FIPS mode installation complete' > /sysroot/etc/system-fips
}

sysroot_bwrap() {
    # Need to work around the initrd `rootfs` / filesystem not being a valid
    # mount to pivot out of. See:
    # https://github.com/torvalds/linux/blob/26bc672134241a080a83b2ab9aa8abede8d30e1c/fs/namespace.c#L3605
    # See similar code in: https://gist.github.com/jlebon/fb6e7c6dcc3ce17d3e2a86f5938ec033
    mkdir -p /mnt/bwrap
    mount --bind / /mnt/bwrap
    mount --make-private /mnt/bwrap
    mount --bind /mnt/bwrap /mnt/bwrap
    for mnt in proc sys dev; do
      mount --bind /$mnt /mnt/bwrap/$mnt
    done
    touch /mnt/bwrap/run/ostree-booted
    mount --bind /sysroot /mnt/bwrap/sysroot
    chroot /mnt/bwrap env --chdir /sysroot bwrap \
        --unshare-pid --unshare-uts --unshare-ipc --unshare-net \
        --unshare-cgroup-try --dev /dev --proc /proc --chdir / \
        --ro-bind usr /usr --bind etc /etc --dir /tmp --tmpfs /var/tmp \
        --tmpfs /run --ro-bind /run/ostree-booted /run/ostree-booted \
        --symlink usr/lib /lib \
        --symlink usr/lib64 /lib64 \
        --symlink usr/bin /bin \
        --symlink usr/sbin /sbin -- "$@"
}

noop() {
    echo "$@"
    exit 0
}

fatal() {
    echo "$@"
    exit 1
}

main "$@"
