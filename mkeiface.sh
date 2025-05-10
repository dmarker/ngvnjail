#!/bin/sh

# This is a slightly gentler way of getting an interface set up in a jail. It
# can still be called from /etc/jail.conf it just cleans that up a little bit.
#
# This + ngportal make adding an interface 2 lines in each jail conf file.

PGM="${0##*/}" # Program basename

CUT=/usr/bin/cut
IFCONFIG=/sbin/ifconfig
KLDLOAD=/sbin/kldload
NGCTL=/usr/sbin/ngctl
SED=/usr/bin/sed


if [ $# -lt 2 -o $# -gt 3 ]; then
	exec >&2
	echo "Usage: $PGM <jail> <ifname> [mac]"
	echo ""
	echo "<jail>   must be an existing jail name or ID."
	echo "<ifname> must be a valid name for an interface and be available"
	echo "         (not yet used) in the <jail>"
	echo "[mac]    must be a valid mac address and if provided it will be"
	echo "         assigned to the ng_eiface(4)"
	echo ""
	echo "Example:"
	echo "    $PGM demo jail0 00:15:5d:01:11:33"
	echo ""
	exit 64  # EX_USAGE from sysexits.h
fi

# give args more useful names for rest of the script
jail=$1
ifname=$2
mac=$3

# module must be loaded before trying to create in a jail
${KLDLOAD} -n ng_eiface

# This returns the interface (not netgraph node) name of the ng_eiface(4) which
# is already renamed. Something like `ngethX`.
mkeiface()
{
	if [ -z $mac ]; then
		${NGCTL} -j $jail -f- <<- EOF | ${SED} '1d' | ${CUT} -d\" -f2
			mkpeer eiface e ether
			name .:e $ifname
			msg .:e getifname
		EOF
	else
		${NGCTL} -j $jail -f- <<- EOF | ${SED} '1d' | ${CUT} -d\" -f2
			mkpeer eiface e ether
			name .:e $ifname
			msg .:e set $mac
			msg .:e getifname
		EOF
	fi
}

# create then name interface in the jail (node already renamed).
${IFCONFIG} -j $jail $(mkeiface) name $ifname
