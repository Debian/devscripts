#!/bin/sh
#
# Copyright 2020 Johannes Schauer Marin Rodrigues <josch@debian.org>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.

# this script is part of debbisect and usually called by debbisect itself
#
# it accepts eight or ten arguments:
#    1. dependencies
#    2. script name or shell snippet
#    3. mirror URL
#    4. architecture
#    5. suite
#    6. components
#    7. memsize
#    8. disksize
#    9. (optional) second mirror URL
#   10. (optional) package to upgrade
#
# It will create an ephemeral qemu virtual machine using mmdebstrap and
# guestfish using (3.) as mirror, (4.) as architecture, (5.) as suite and
# (6.) as components, install the dependencies given in (1.) and execute the
# script given in (2.).
# Its output is the exit code of the script as well as a file ./pkglist
# containing the output of "dpkg-query -W" inside the chroot.
#
# If not only six but eight arguments are given, then the second mirror URL
# (9.) will be added to the apt sources and the single package (10.) will be
# upgraded to its version from (9.).

set -exu

if [ $# -ne 8 ] && [ $# -ne 10 ]; then
	echo "usage: $0 depends script mirror1 architecture suite components memsize disksize [mirror2 toupgrade]"
	exit 1
fi

depends=$1
script=$2
mirror1=$3
architecture=$4
suite=$5
components=$6
memsize=$7
disksize=$8

if [ $# -eq 10 ]; then
	mirror2=$9
	toupgrade=${10}
fi

case $architecture in
	alpha)    qemuarch=alpha;;
	amd64)    qemuarch=x86_64;;
	arm)      qemuarch=arm;;
	arm64)    qemuarch=aarch64;;
	armel)    qemuarch=arm;;
	armhf)    qemuarch=arm;;
	hppa)     qemuarch=hppa;;
	i386)     qemuarch=i386;;
	m68k)     qemuarch=m68k;;
	mips)     qemuarch=mips;;
	mips64)   qemuarch=mips64;;
	mips64el) qemuarch=mips64el;;
	mipsel)   qemuarch=mipsel;;
	powerpc)  qemuarch=ppc;;
	ppc64)    qemuarch=ppc64;;
	ppc64el)  qemuarch=ppc64le;;
	riscv64)  qemuarch=riscv64;;
	s390x)    qemuarch=s390x;;
	sh4)      qemuarch=sh4;;
	sparc)    qemuarch=sparc;;
	sparc64)  qemuarch=sparc64;;
	*) echo "no qemu support for $architecture"; exit 1;;
esac
case $architecture in
	i386)     linuxarch=686-pae;;
	amd64)    linuxarch=amd64;;
	arm64)    linuxarch=arm64;;
	armhf)    linuxarch=armmp;;
	ia64)     linuxarch=itanium;;
	m68k)     linuxarch=m68k;;
	armel)    linuxarch=marvell;;
	hppa)     linuxarch=parisc;;
	powerpc)  linuxarch=powerpc;;
	ppc64)    linuxarch=powerpc64;;
	ppc64el)  linuxarch=powerpc64le;;
	riscv64)  linuxarch=riscv64;;
	s390x)    linuxarch=s390x;;
	sparc64)  linuxarch=sparc64;;
	*) echo "no kernel image for $architecture"; exit 1;;
esac

TMPDIR=$(mktemp --tmpdir --directory debbisect_qemu.XXXXXXXXXX)
cleantmp() {
	for f in customize.sh id_rsa id_rsa.pub qemu.log config; do
		rm -f "$TMPDIR/$f"
	done
	rmdir "$TMPDIR"
}

trap cleantmp EXIT
# the temporary directory must be world readable (for example in unshare mode)
chmod a+xr "$TMPDIR"

ssh-keygen -q -t rsa -f "$TMPDIR/id_rsa" -N ""

cat << SCRIPT > "$TMPDIR/customize.sh"
#!/bin/sh
set -exu

rootfs="\$1"

# setup various files in /etc
echo host > "\$rootfs/etc/hostname"
echo "127.0.0.1 localhost host" > "\$rootfs/etc/hosts"
echo "/dev/vda1 / auto errors=remount-ro 0 1" > "\$rootfs/etc/fstab"
cat /etc/resolv.conf > "\$rootfs/etc/resolv.conf"

# setup users
chroot "\$rootfs" passwd --delete root
chroot "\$rootfs" useradd --home-dir /home/user --create-home user
chroot "\$rootfs" passwd --delete user

# extlinux config to boot from /dev/vda1 with predictable network interface
# naming and a serial console for logging
cat << END > "\$rootfs/extlinux.conf"
default linux
timeout 0

label linux
kernel /vmlinuz
append initrd=/initrd.img root=/dev/vda1 net.ifnames=0 console=ttyS0
END

# network interface config
# we can use eth0 because we boot with net.ifnames=0 for predictable interface
# names
cat << END > "\$rootfs/etc/network/interfaces"
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
END

# copy in the public key
mkdir "\$rootfs/root/.ssh"
cp "$TMPDIR/id_rsa.pub" "\$rootfs/root/.ssh/authorized_keys"
chroot "\$rootfs" chown 0:0 /root/.ssh/authorized_keys
SCRIPT
chmod +x "$TMPDIR/customize.sh"

mmdebstrap --architecture=$architecture --verbose --variant=apt --components="$components" \
	--aptopt='Acquire::Check-Valid-Until "false"' \
	--include='openssh-server,systemd-sysv,ifupdown,netbase,isc-dhcp-client,udev,policykit-1,linux-image-'"$linuxarch" \
	--customize-hook="$TMPDIR/customize.sh" \
	"$suite" debian-rootfs.tar "$mirror1"

# use guestfish to prepare the host system
#
#  - create a single 4G partition and unpack the rootfs tarball into it
#  - unpack the tarball of the container into /
#  - put a syslinux MBR into the first 440 bytes of the drive
#  - install extlinux and make partition bootable
#
# useful stuff to debug any errors:
#   LIBGUESTFS_BACKEND_SETTINGS=force_tcg
#   libguestfs-test-tool || true
#   export LIBGUESTFS_DEBUG=1 LIBGUESTFS_TRACE=1
guestfish -N "debian-rootfs.img"=disk:$disksize -- \
	part-disk /dev/sda mbr : \
	mkfs ext4 /dev/sda1 : \
	mount /dev/sda1 / : \
	tar-in "debian-rootfs.tar" / : \
	upload /usr/lib/SYSLINUX/mbr.bin /mbr.bin : \
	copy-file-to-device /mbr.bin /dev/sda size:440 : \
	rm /mbr.bin : \
	extlinux / : \
	sync : \
	umount / : \
	part-set-bootable /dev/sda 1 true : \
	shutdown


# start the host system
# prefer using kvm but fall back to tcg if not available
# avoid entropy starvation by feeding the crypt system with random bits from /dev/urandom
# the default memory size of 128 MiB is not enough for Debian, so we go with 1G
# use a virtio network card instead of emulating a real network device
# we don't need any graphics
# this also multiplexes the console and the monitor to stdio
# creates a multiplexed stdio backend connected to the serial port and the qemu
# monitor
# redirect tcp connections on port 10022 localhost to the host system port 22
# redirect all output to a file
# run in the background
timeout --kill-after=60s 60m \
	qemu-system-"$qemuarch" \
	-M accel=kvm:tcg \
	-no-user-config \
	-object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0 \
	-m $memsize \
	-net nic,model=virtio \
	-nographic \
	-serial mon:stdio \
	-net user,hostfwd=tcp:127.0.0.1:10022-:22 \
	-drive file="debian-rootfs.img",format=raw,if=virtio \
	> "$TMPDIR/qemu.log" </dev/null 2>&1 &

# store the pid
QEMUPID=$!

# use a function here, so that we can properly quote the path to qemu.log
showqemulog() {
	cat --show-nonprinting "$TMPDIR/qemu.log"
}

# show the log and kill qemu in case the script exits first
trap "showqemulog; cleantmp; kill $QEMUPID" EXIT

# the default ssh command does not store known hosts and even ignores host keys
# it identifies itself with the rsa key generated above
# pseudo terminal allocation is disabled or otherwise, programs executed via
# ssh might wait for input on stdin of the ssh process

cat << END > "$TMPDIR/config"
Host qemu
	Hostname 127.0.0.1
	User root
	Port 10022
	UserKnownHostsFile /dev/null
	StrictHostKeyChecking no
	IdentityFile $TMPDIR/id_rsa
	RequestTTY no
END

TIMESTAMP=$(sleepenh 0 || [ $? -eq 1 ])
TIMEOUT=5
NUM_TRIES=40
i=0
while true; do
	rv=0
	ssh -F "$TMPDIR/config" -o ConnectTimeout=$TIMEOUT qemu echo success || rv=1
	[ $rv -eq 0 ] && break
	# if the command before took less than $TIMEOUT seconds, wait the remaining time
	TIMESTAMP=$(sleepenh $TIMESTAMP $TIMEOUT || [ $? -eq 1 ]);
	i=$((i+1))
	if [ $i -ge $NUM_TRIES ]; then
		break
	fi
done

if [ $i -eq $NUM_TRIES ]; then
	echo "timeout reached: unable to connect to qemu via ssh"
	exit 1
fi

# if any url in sources.list points to 127.0.0.1 then we have to replace them
# by the host IP as seen by the qemu guest
cat << SCRIPT | ssh -F "$TMPDIR/config" qemu sh
set -eu
if [ -e /etc/apt/sources.list ]; then
	sed -i 's/http:\/\/127.0.0.1:/http:\/\/10.0.2.2:/' /etc/apt/sources.list
fi
find /etc/apt/sources.list.d -type f -name '*.list' -print0 \
	| xargs --null --no-run-if-empty sed -i 's/http:\/\/127.0.0.1:/http:\/\/10.0.2.2:/'
SCRIPT

# we install dependencies now and not with mmdebstrap --include in case some
# dependencies require a full system present
ssh -F "$TMPDIR/config" qemu apt-get update
ssh -F "$TMPDIR/config" qemu env DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true apt-get --yes install --no-install-recommends $(echo $depends | tr ',' ' ')

# in its ten-argument form, a single package has to be upgraded to its
# version from the first bad timestamp
if [ $# -eq 10 ]; then
	# replace content of sources.list with first bad timestamp
	mirror2=$(echo "$mirror2" | sed 's/http:\/\/127.0.0.1:/http:\/\/10.0.2.2:/')
	echo "deb $mirror2 $suite $(echo "$components" | tr ',' ' ')" | ssh -F "$TMPDIR/config" qemu "cat > /etc/apt/sources.list"
	ssh -F "$TMPDIR/config" qemu apt-get update
	# upgrade a single package (and whatever else apt deems necessary)
	before=$(ssh -F "$TMPDIR/config" qemu dpkg-query -W)
	ssh -F "$TMPDIR/config" qemu env DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true apt-get --yes install --no-install-recommends "$toupgrade"
	after=$(ssh -F "$TMPDIR/config" qemu dpkg-query -W)
	# make sure that something was upgraded
	if [ "$before" = "$after" ]; then
		echo "nothing got upgraded -- this should never happen" >&2
		exit 1
	fi
	ssh -F "$TMPDIR/config" qemu dpkg-query -W > "./debbisect.$DEBIAN_BISECT_TIMESTAMP.$toupgrade.pkglist"
else
	ssh -F "$TMPDIR/config" qemu dpkg-query -W > "./debbisect.$DEBIAN_BISECT_TIMESTAMP.pkglist"
fi

ssh -F "$TMPDIR/config" qemu dpkg -l

# explicitly export all necessary variables
# because we use set -u this also makes sure that this script has these
# variables set in the first place
export DEBIAN_BISECT_EPOCH=$DEBIAN_BISECT_EPOCH
export DEBIAN_BISECT_TIMESTAMP=$DEBIAN_BISECT_TIMESTAMP
if [ -z ${DEBIAN_BISECT_MIRROR+x} ]; then
	# DEBIAN_BISECT_MIRROR was unset (caching is disabled)
	true
else
	# replace the localhost IP by the IP of the host as seen by qemu
	DEBIAN_BISECT_MIRROR=$(echo "$DEBIAN_BISECT_MIRROR" | sed 's/http:\/\/127.0.0.1:/http:\/\/10.0.2.2:/')
	export DEBIAN_BISECT_MIRROR=$DEBIAN_BISECT_MIRROR
fi


# either execute $script as a script from $PATH or as a shell snippet
ret=0
if [ -x "$script" ] || echo "$script" | grep --invert-match --silent --perl-regexp '[^\w@\%+=:,.\/-]'; then
	"$script" "$TMPDIR/config" || ret=$?
else
	sh -c "$script" exec "$TMPDIR/config" || ret=$?
fi

# since we installed systemd-sysv, systemctl is available
ssh -F "$TMPDIR/config" qemu systemctl poweroff

wait $QEMUPID

trap - EXIT

showqemulog
cleantmp

if [ "$ret" -eq 0 ]; then
	exit 0
else
	exit 1
fi
