#!/bin/bash -e

#	Written by curaga.
#
#	Sorts out all built modules to module extensions, and a tarball for what goes in the base.
#
#	Before running, do a "make INSTALL_MOD_PATH=/tmp/somewhere/usr/local modules_install" and
#	any other preprocessing, like gzipping the modules and removing generated files in
#	lib/modules/KERNELVER.
#	Things will happen in the current directory.
#
#
#	Usage:		./sorter.sh KERNELVER PATH
#	Example:	./sorter.sh 2.6.33-tinycore /tmp/somewhere
#
# --------------- Changes ---------------
# 07/27/2020 Ver. 1.20 Rich
# Added this change log.
# Added functions Apply(), SetArch(), and Usage().
# Added conditional execution of lines calling packup() based on $Arch.
#       This allows for tailoring of packages to processor type if required.
# Added some more error checking and messages.
# 
#
# ------------- End Changes ---------------

# Architecture based on kernel name, i.e KERNEL-piCore-7l == arm7l
Arch=""
# Flag used in lines calling packup(). When set to 1, that line gets executed.
DoIt=0
# Dependencies this script requires to run.
RequiredDeps="bash squashfs-tools zsync"
# Dependencies this script could not find.
MissingDeps=""
# Usage message.
UsageMsg="\nUsage: `basename $0` KERNELVER PATH\n"

# Error flags	
BadPATH=0
BadKERNELVER=0
Bailout=0

# Number of arguments passed to this script.
ArgCount=$#

# Predefined strings which can be passed to Apply() as its second parameter.
AllCPUs="x86 x86_64 arm6 arm7 arm7l arm7l+"
ArmCPUs="arm6 arm7 arm7l arm7l+"
IntelCPUs="x86 x86_64"

alias basename='busybox basename'
# Having findutils installed breaks this script.
alias find='busybox find'

# ------------------------------ Functions ------------------------------
Apply()
{
# Test if word in $1 matches any words in $2.
# Sets DoIt to 1 if match is found.
	DoIt=0
	for TestString in $2
	do
		if [ "$TestString" == "$1" ]
		then
			DoIt=1
			break
		fi
	done
}


packup() {

	cd $BASEPATH

	OLDDIR=$OLDPWD
	TARBALL=$1
	shift


	rm -rf /tmp/xtra
	> /tmp/list
	for i in $@; do
		find usr/local/lib/modules/$KERNEL/kernel/${i} -type f >> /tmp/list
	done

	tar -cvzf ${OLDDIR}/${TARBALL}.tgz -T /tmp/list
	for g in `cat /tmp/list`; do rm $g; done

	mkdir /tmp/xtra
	tar -C /tmp/xtra -xf ${OLDDIR}/${TARBALL}.tgz
	cd /tmp
	mksquashfs xtra ${TARBALL}.tcz
	md5sum ${TARBALL}.tcz > $OLDDIR/${TARBALL}.tcz.md5.txt
	zsyncmake -u ${TARBALL}.tcz ${TARBALL}.tcz

	mv ${TARBALL}.tcz* $OLDDIR

	find xtra -type f -exec modinfo '{}' \; >> ${OLDDIR}/${TARBALL}.moddeps
	grep depends: ${OLDDIR}/${TARBALL}.moddeps | cut -d: -f2 | sed -e 's@^[ ]*@@' -e '/^$/d' -e 's@,@\n@g' |
		sort | uniq > /tmp/tmpdeps
	mv /tmp/tmpdeps ${OLDDIR}/${TARBALL}.moddeps

	cd xtra
	find -type f > ${OLDDIR}/${TARBALL}.tcz.list

	rm ${OLDDIR}/${TARBALL}.tgz

	cd $OLDDIR

	# Clean the moddeps up a bit, remove everything in the same file
	for i in `cat ${TARBALL}.moddeps`; do
		grep -q "${i}.ko" ${TARBALL}.tcz.list && sed -i "/^${i}$/d" ${TARBALL}.moddeps
	done
	[ -s ${TARBALL}.moddeps ] || rm ${TARBALL}.moddeps
}


SetArch()
{
	case "$1" in
		*core) Arch="x86";;
		*core64) Arch="x86_64";;
		*Core) Arch="arm6";;
		*Core-v7) Arch="arm7";;
		*Core-v7l) Arch="arm7l";;
		*Core-v7l+) Arch="arm7l+";;
		*) Arch="Error";;
	esac
}


Usage()
{
	[ -n "$MissingDeps" ] && echo -e "\n`basename $0` needs the following packages to run:\n\n\t$MissingDeps\n"

	if [ "$BadPATH" -ne 0 ]
	then
		echo -e "$UsageMsg"
		echo -e "Invalid PATH specified\n"
		exit 1
	else
		# We can only flag a bad $KERNELVER if $PATH is valid.
		if [ "$BadKERNELVER" -ne 0 ]
		then
			echo -e "$UsageMsg"
			echo -e "Invalid KERNELVER specified\n"
			exit 1
		fi
	fi

	[ $ArgCount -eq 2 ] && exit 1
	# If we get to here, not enough parameters were supplied to the script.
	echo -e "$UsageMsg"
	echo -e "`basename $0` requires 2 arguments, you provided $ArgCount\n"
	exit 1
}

# ---------------------------- End Functions ----------------------------


# Main

# Check for missing dependencies.
for Dep in $RequiredDeps
do
	[ ! -f "/usr/local/tce.installed/$Dep" ] && MissingDeps="$MissingDeps$Dep " && Bailout=1
done

# No point in testing PATH or KERNELVER if the correct number of arguments were not supplied.
[ $ArgCount -ne 2 ] && Usage

KERNEL=$1
BASEPATH=$2

# Testing for valid PATH and KERNELVER valus.
[ ! -e ${BASEPATH}/usr/local/lib/modules ] && BadPATH=1
[ ! -e ${BASEPATH}/usr/local/lib/modules/${KERNEL} ] && BadKERNELVER=1

# Call Usage() if any of these variable is not zero.
[ $((BadPATH + BadKERNELVER + Bailout)) -ne 0 ] && Usage

# Packing up

# This sets the $Arch variable used in the Apply() calls.
SetArch $KERNEL

echo Sorting $KERNEL modules from $BASEPATH

Apply "$Arch" "$IntelCPUs"; [ "$DoIt" = 1 ] && packup kvm-$KERNEL arch/x86/kvm/*

Apply "$Arch" "$AllCPUs"; [ "$DoIt" = 1 ] && packup filesystems-$KERNEL fs/[bcehjmrux]*/* fs/nfsd/* fs/nfs fs/nilfs2

Apply "$Arch" "$IntelCPUs"; [ "$DoIt" = 1 ] && packup alsa-modules-$KERNEL sound
Apply "$Arch" "$ArmCPUs"; [ "$DoIt" = 1 ] && packup alsa-modules-$KERNEL sound drivers/clk drivers/staging/vc04_services/bcm2835-audio

Apply "$Arch" "$IntelCPUs"; [ "$DoIt" = 1 ] && packup bluetooth-$KERNEL net/bluetooth drivers/bluetooth
Apply "$Arch" "$ArmCPUs"; [ "$DoIt" = 1 ] && packup bluetooth-$KERNEL net/bluetooth drivers/bluetooth crypto/ecc* crypto/ecdh*

#packup irda-$KERNEL net/irda drivers/net/irda drivers/usb/serial/ir-usb*
Apply "$Arch" "$AllCPUs"; [ "$DoIt" = 1 ] && packup net-bridging-$KERNEL net/bridge
Apply "$Arch" "$AllCPUs"; [ "$DoIt" = 1 ] && packup net-sched-$KERNEL net/sched
Apply "$Arch" "$AllCPUs"; [ "$DoIt" = 1 ] && packup ipv6-netfilter-$KERNEL net/ipv6 net/ipv4 net/netfilter
Apply "$Arch" "$AllCPUs"; [ "$DoIt" = 1 ] && packup wireless-$KERNEL net/mac80211 net/wireless drivers/net/wireless

Apply "$Arch" "$IntelCPUs"; [ "$DoIt" = 1 ] && packup nouveau-$KERNEL drivers/gpu/drm/nouveau

Apply "$Arch" "$IntelCPUs"; [ "$DoIt" = 1 ] && packup graphics-$KERNEL drivers/char/agp drivers/gpu drivers/usb/misc/sisusbvga
Apply "$Arch" "$ArmCPUs"; [ "$DoIt" = 1 ] && packup graphics-$KERNEL drivers/gpu drivers/video drivers/staging/fbtft drivers/media/cec

Apply "$Arch" "$IntelCPUs"; [ "$DoIt" = 1 ] && packup firewire-$KERNEL drivers/firewire

Apply "$Arch" "$AllCPUs"; [ "$DoIt" = 1 ] && packup hwmon-$KERNEL drivers/hwmon
Apply "$Arch" "$AllCPUs"; [ "$DoIt" = 1 ] && packup i2c-$KERNEL drivers/i2c
Apply "$Arch" "$AllCPUs"; [ "$DoIt" = 1 ] && packup raid-dm-$KERNEL drivers/md lib/raid*
Apply "$Arch" "$AllCPUs"; [ "$DoIt" = 1 ] && packup input-joystick-$KERNEL drivers/input/joy* drivers/input/gameport

Apply "$Arch" "$IntelCPUs"; [ "$DoIt" = 1 ] && packup input-tablet-touchscreen-$KERNEL drivers/input/tablet drivers/input/touchscreen
Apply "$Arch" "$ArmCPUs"; [ "$DoIt" = 1 ] && packup input-tablet-touchscreen-$KERNEL drivers/input/touchscreen

Apply "$Arch" "$AllCPUs"; [ "$DoIt" = 1 ] && packup v4l-dvb-$KERNEL drivers/media drivers/usb/misc/isight*
Apply "$Arch" "$AllCPUs"; [ "$DoIt" = 1 ] && packup mtd-$KERNEL drivers/mtd

Apply "$Arch" "$IntelCPUs"; [ "$DoIt" = 1 ] && packup usb-serial-$KERNEL drivers/usb/misc/uss* drivers/usb/serial
Apply "$Arch" "$ArmCPUs"; [ "$DoIt" = 1 ] && packup usb-serial-$KERNEL drivers/usb/serial

Apply "$Arch" "$AllCPUs"; [ "$DoIt" = 1 ] && packup leds-$KERNEL drivers/leds
Apply "$Arch" "$AllCPUs"; [ "$DoIt" = 1 ] && packup wimax-$KERNEL net/wimax drivers/net/wimax

Apply "$Arch" "$IntelCPUs"; [ "$DoIt" = 1 ] && packup pci-hotplug-$KERNEL drivers/pci/hotplug
Apply "$Arch" "$IntelCPUs"; [ "$DoIt" = 1 ] && packup thinkpad-acpi-$KERNEL drivers/platform/x86/thinkpad_acpi*

Apply "$Arch" "$AllCPUs"; [ "$DoIt" = 1 ] && packup watchdog-$KERNEL drivers/watchdog
Apply "$Arch" "$AllCPUs"; [ "$DoIt" = 1 ] && packup ax25-$KERNEL net/ax25 net/rose net/netrom drivers/net/hamradio

Apply "$Arch" "$ArmCPUs"; [ "$DoIt" = 1 ] && packup net-usb-$KERNEL drivers/net/usb
Apply "$Arch" "$ArmCPUs"; [ "$DoIt" = 1 ] && packup ppp-modules-$KERNEL drivers/net/ppp drivers/net/slip
Apply "$Arch" "$ArmCPUs"; [ "$DoIt" = 1 ] && packup rtc-$KERNEL drivers/rtc
Apply "$Arch" "$ArmCPUs"; [ "$DoIt" = 1 ] && packup w1-$KERNEL drivers/w1
Apply "$Arch" "$ArmCPUs"; [ "$DoIt" = 1 ] && packup usbip-$KERNEL drivers/usb/usbip
Apply "$Arch" "$ArmCPUs"; [ "$DoIt" = 1 ] && packup can-modules-$KERNEL drivers/net/can net/can

# Needs to go to the base.
Apply "$Arch" "$IntelCPUs"; [ "$DoIt" = 1 ] && mv ${BASEPATH}/usr/local/lib/modules/${KERNEL}/kernel/drivers/scsi/hv_* /tmp
Apply "$Arch" "$IntelCPUs"; [ "$DoIt" = 1 ] && mv ${BASEPATH}/usr/local/lib/modules/${KERNEL}/kernel/drivers/scsi/scsi_transport_fc* /tmp
Apply "$Arch" "$IntelCPUs"; [ "$DoIt" = 1 ] && packup scsi-$KERNEL drivers/scsi drivers/message

Apply "$Arch" "$AllCPUs"; [ "$DoIt" = 1 ] && packup l2tp-$KERNEL net/l2tp
Apply "$Arch" "$AllCPUs"; [ "$DoIt" = 1 ] && packup sctp-$KERNEL net/sctp

# Meta-extension for original modules
EMPTYD=`mktemp -d`
mkdir -p ${EMPTYD}/lib
ls *.tcz > original-modules-$KERNEL.tcz.dep
mksquashfs $EMPTYD original-modules-$KERNEL.tcz
md5sum original-modules-$KERNEL.tcz > original-modules-$KERNEL.tcz.md5.txt
zsyncmake -u original-modules-$KERNEL.tcz original-modules-$KERNEL.tcz
rm -rf $EMPTYD

# The rest goes to the base.

# ARM exits here (at least for now).
Apply "$Arch" "$ArmCPUs"; [ "$DoIt" = 1 ] && echo "`ls -1 *.tcz | wc -l` ARM Modules done. Skipping commands for base." && exit

mv /tmp/hv_* /tmp/scsi_transport_fc* ${BASEPATH}/usr/local/lib/modules/${KERNEL}/kernel/drivers/scsi/
cd ${BASEPATH}/usr/local
ln -s /usr/local/lib/modules/${KERNEL}/kernel/ lib/modules/${KERNEL}/kernel.tclocal
mkdir -p usr/local/lib/modules/${KERNEL}/kernel/
find lib/modules ! -type d > /tmp/list
echo usr/local/lib/modules/${KERNEL}/kernel/ >> /tmp/list
tar cvzf ${OLDPWD}/base_modules.tgz -T /tmp/list

cd -

cp /tmp/list base_modules.tgz.list

# Is it 64-bit?
is64=
case $KERNEL in *64) is64=64 ;; esac

# Also convert it to the cpio initrd format
mkdir tmp
cd tmp
tar xf ../base_modules.tgz
depmod -a -b . ${KERNEL}
rm -f lib/modules/${KERNEL}/*map
rm lib/modules/${KERNEL}/modules.symbols
find lib usr | cpio -o -H newc | gzip -9 > ../modules${is64}.gz

cd ..
rm -rf tmp

# Some final moddeps cleanup
for i in `grep gz base_modules.tgz.list | sed -e 's@.*/@@' -e 's@.ko.gz@@'`; do sed "/^$i\$/d" *moddeps -i; done
for i in *moddeps; do [ -s $i ] || rm $i; done

echo -e "\n\n"'Done!'
