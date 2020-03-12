#!/bin/bash
set -euo pipefail

outputdir=$1; shift
ign_config=$1; shift
wanted_path=$1; shift

# Hack: we ask Ignition to write out the files in a temporary rootfs so we can
# extract the one file we want from there. We don't want to actually run after
# ignition-files because by then it'll be much too late.

# Note this won't work if the file you're interested in might possibly be on a
# separate partition. `/etc/*` is safe, but e.g. `/var/lib/containers/foo.json`
# will fail hard if someone wants a partition for `/var/lib/containers`. This is
# a problem intrinsic to the Ignition v2 spec.

tmpsysroot=${outputdir}/sysroot
tmpconfig=${outputdir}/tmpconfig.json
mkdir -p "${tmpsysroot}"

# print out the logs only if something went wrong
trap "cat ${outputdir}/ignition.log" ERR

# select just the entry we care about, and scrub out user/group, which would
# require passwd lookups too
(jq ".storage.files[] | select(.path==\"${wanted_path}\") | del(.user, .group)" 2>/dev/null || :) \
    < "${ign_config}" > ${tmpconfig}.fragment
if [ ! -s ${tmpconfig}.fragment ]; then
    exit 0
fi

# make a super minimal Ignition config that just has that, so there are no
# other side-effects (e.g. requirements on passwd, or partitions)
cat > "${tmpconfig}" <<EOF
{
    "ignition": {"version": $(jq .ignition.version < ${ign_config})},
    "storage": {
        "files": [
            $(cat ${tmpconfig}.fragment)
        ]
    }
}
EOF

/usr/bin/ignition \
  --config-cache "${tmpconfig}" \
  --root="${tmpsysroot}" --oem="${OEM_ID}" --stage=files \
  --log-to-stdout &> "${outputdir}/ignition.log"
