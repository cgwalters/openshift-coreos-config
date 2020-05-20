#!/bin/bash
# This test is a dumping ground for quick read-only tests.
set -xeuo pipefail

cd $(mktemp -d)

# Ensure we have tmpfs on /tmp like Fedora(FCOS)
tmpfs=$(findmnt -n -o FSTYPE /tmp)
if [ "${tmpfs}" != "tmpfs" ]; then
  echo "Expected tmpfs on /tmp, found: ${tmpfs}"
  exit 1
fi
echo "ok tmpfs"

# SELinux should be on except in live OS
if ! [ -f /run/ostree-live ]; then
  enforce=$(getenforce)
  if [ "${enforce}" != "Enforcing" ]; then
    echo "Expected SELinux Enforcing, found ${enforce}"
    exit 1
  fi
fi
echo "ok selinux"

# https://bugzilla.redhat.com/show_bug.cgi?id=1830280
case "$(arch)" in
  x86_64)
    dmesg | grep ' random:' > random.txt
    if ! grep -qe 'crng done.*trust.*CPU' <random.txt; then
      echo "Failed to find crng trusting CPU"
      sed -e 's/^/# /' < random.txt
      exit 1
    fi
    echo "ok random trust cpu" ;;
  *) echo "Don't know how to test hardware RNG state on arch=$(arch)" ;;
esac
