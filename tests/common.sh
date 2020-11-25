#!/bin/bash
#
# Copyright 2020 Nikos Mavrogiannopoulos
#
# This file is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This file is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this file; if not, write to the Free Software Foundation,
# Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.

builddir=${builddir:-.}
srcdir=${srcdir:-.}

OPENCONNECT=${OPENCONNECT:-$(which openconnect)}
OCCTL=${OCCTL:-$(which occtl)}
OCSERV=${OCSERV:-$(which ocserv)}
IP=${IP:-$(which ip)}

if test -z "${OPENCONNECT}" || ! test -x ${OPENCONNECT};then
	echo "You need openconnect to run this test"
	exit 1
fi

if test -z "${OCSERV}" || ! test -x ${OCSERV};then
	echo "You need openconnect to run this test"
	exit 1
fi

if test -z "$NO_NEED_ROOT";then
	if test "$(id -u)" != "0";then
		echo "You need to run this script as root"
		exit 77
	fi
fi

update_config() {
	file=$1
	username=$(whoami)
	group=$(groups|cut -f 1 -d ' ')

	if test -z "${ISOLATE_WORKERS}";then
		if test "${COVERAGE}" = "1";then
			ISOLATE_WORKERS=false
		else
			ISOLATE_WORKERS=true
		fi
	fi

	cp "${srcdir}/data/${file}" "$file.$$.tmp"
	sed -i -e 's|@USERNAME@|'${username}'|g' "$file.$$.tmp" \
	       -e 's|@GROUP@|'${group}'|g' "$file.$$.tmp" \
	       -e 's|@SRCDIR@|'${srcdir}'|g' "$file.$$.tmp" \
	       -e 's|@ISOLATE_WORKERS@|'${ISOLATE_WORKERS}'|g' "$file.$$.tmp" \
	       -e 's|@OTP_FILE@|'${OTP_FILE}'|g' "$file.$$.tmp" \
	       -e 's|@CRLNAME@|'${CRLNAME}'|g' "$file.$$.tmp" \
	       -e 's|@PORT@|'${PORT}'|g' "$file.$$.tmp" \
	       -e 's|@DNS@|'${DNS}'|g' "$file.$$.tmp" \
	       -e 's|@ADDRESS@|'${ADDRESS}'|g' "$file.$$.tmp" \
	       -e 's|@VPNNET@|'${VPNNET}'|g' "$file.$$.tmp" \
	       -e 's|@VPNNET6@|'${VPNNET6}'|g' "$file.$$.tmp" \
	       -e 's|@ROUTE1@|'${ROUTE1}'|g' "$file.$$.tmp" \
	       -e 's|@ROUTE2@|'${ROUTE2}'|g' "$file.$$.tmp" \
	       -e 's|@NOROUTE1@|'${NOROUTE1}'|g' "$file.$$.tmp" \
	       -e 's|@NOROUTE2@|'${NOROUTE2}'|g' "$file.$$.tmp" \
	       -e 's|@MATCH_CIPHERS@|'${MATCH_CIPHERS}'|g' "$file.$$.tmp" \
	       -e 's|@OCCTL_SOCKET@|'${OCCTL_SOCKET}'|g' "$file.$$.tmp" \
	       -e 's|@LISTEN_NS@|'${LISTEN_NS}'|g' "$file.$$.tmp"
	CONFIG="$file.$$.tmp"
}

# Check for a utility to list ports.  Both ss and netstat will list
# ports for normal users, and have similar semantics, so put the
# command in the caller's PFCMD, or exit, indicating an unsupported
# test.  Prefer ss from iproute2 over the older netstat.
have_port_finder() {
	for file in $(which ss 2> /dev/null) /*bin/ss /usr/*bin/ss /usr/local/*bin/ss;do
		if test -x "$file";then
			PFCMD="$file";return 0
		fi
	done

	if test -z "$PFCMD";then
	for file in $(which netstat 2> /dev/null) /bin/netstat /usr/bin/netstat /usr/local/bin/netstat;do
		if test -x "$file";then
			PFCMD="$file";return 0
		fi
	done
	fi

	if test -z "$PFCMD";then
		echo "neither ss nor netstat found"
		exit 1
	fi
}

check_if_port_in_use() {
	local PORT="$1"
	local PFCMD; have_port_finder
	$PFCMD -an|grep "[\:\.]$PORT" >/dev/null 2>&1
}

# Find a port number not currently in use.
GETPORT='
    rc=0
    unset myrandom
    while test $rc = 0; do
        if test -n "$RANDOM"; then myrandom=$(($RANDOM + $RANDOM)); fi
        if test -z "$myrandom"; then myrandom=$(date +%N | sed s/^0*//); fi
        if test -z "$myrandom"; then myrandom=0; fi
        PORT="$(((($$<<15)|$myrandom) % 63001 + 2000))"
        check_if_port_in_use $PORT;rc=$?
    done
'

