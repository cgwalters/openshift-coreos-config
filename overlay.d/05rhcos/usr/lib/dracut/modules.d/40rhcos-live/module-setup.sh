#!/bin/bash

check() {
    return 0
}

install_unit() {
    local unit=$1; shift
    local target=${1:-ignition-complete.target}
    inst_simple "$moddir/$unit" "$systemdsystemunitdir/$unit"
    local targetpath="$systemdsystemunitdir/${target}.requires/"
    mkdir -p "${initdir}/${targetpath}"
    ln_r "../$unit" "${targetpath}/${unit}"
}

depends() {
    echo
}

install() {
    install_unit "rhcos-live-selinux.service" "initrd.target"
}
