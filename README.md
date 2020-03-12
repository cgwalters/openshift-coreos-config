This is intended to be the "upstream" of RHEL CoreOS, using
[CentOS Stream](https://wiki.centos.org/Manuals/ReleaseNotes/CentOSStream)

It doesn't build yet because we need to also build some CoreOS
components like `afterburn` targeting this userspace, and we
also need to figure out where to get stuff like `openvswitch`.

Possibly in the future, what we can do is have redhat-coreos
inherit *this* as a git submodule.
