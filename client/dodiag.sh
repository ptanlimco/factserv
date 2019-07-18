#!/bin/sh -eu

# This script is part of the diagnostic tarball. It is run by startdiag.sh to
# do all deferrable initialization and then run dodiag to actiually perform
# the tests.

# Abort with message
die() { echo $* >&2; exit 1; }

[ $# = 3 ] || die "Usage: dodiag.sh pionicIP serverIP buildID"
pionicIP=$1 serverIP=$2 buildID=$3

# The current directory contains the downloaded diagnostics, make sure that the
# dodiag program is there.
[ -x ./dodiag ] || die "No executable dodiag"

# XXX do board-specific pre-diag initialization here, start daemons and insmod device
# drivers, etc, in preparation for performing diagnostics.

# XXX get the device ID from permanent storage here. If device ID is not
# currently programmed then leave as "" and the system will scan the barcode
# from the PCB and then perform phase 1 tests (which must include installation
# of the device ID).
deviceID=""

# Now invoke dodiag 
./dodiag -p $pionicIP -s $serverIP $buildID $deviceID
exs=$?
echo "dodiag exit with status $exs"
exit $exs
