#!/bin/sh -eu

# Diagnostic startup, this script is part of published root and runs as early
# as possible during boot.

# This is the pionic controller's IP address, as defined in pionic.cfg.
pionicIP=192.168.111.1  # pionic controller IP address

# This is the factory detction method. If the DUT has a pre-defined static IP
# address at the time that this script runs, then use 'http'. Otherwise use
# 'beacon' (and "use_beacon" must be enabled in pionic.cfg).
method=http             

# If 'beacon', this is the network interface that attaches to the pionic
# controller. Not required for http since the network must already be up.
interface=

# If 'beacon', the IP address to apply to the interface after beacon is
# detected (in the same subnet as pionic). Not required for http since the
# network must already be up.
localIP=

# The factory server has a self-signed https certificate. This is base-64
# encoded sha256 of the cert's public key. NOTE your key MUST be kept secret or
# end-users will be able to take over your systems.
pubkey="paYQewbP520iAv1hIi/A1lvYyVzMdDv6yEmp9El0aPc="     

# We assume it's not possible to properly recover from diagnostic mode without
# a full reboot, therefore this script spins forever on any non-zero exit
# status.
trap '[ $? != 0 ] && while true; do echo "Reboot now"; sleep 5; done' EXIT 

# die with message to stderr
die() { echo $* >&2; exit 1; }

# First, try to detect the factory.
if [ $method == beacon ]; then
    # beacon mode, listen for an ethernet beacon
    beacon recv 2 $interface pionic >/dev/null || exit 0 
    # There is no exit after this point
    echo "Beacon detected, configuring $interface for $localIP"
    ip link set $interface up || true
    ip address add $localIP dev $interface || true
    echo "Fetching server IP from pionic"
    serverIP=$(curl -qsf -m3  "http://$pionicIP/factory") || die "Failed"
else
    # http mode, we assume $pionicIP is on the local subnet
    serverIP=$(curl -qsf -m3  "http://$pionicIP/factory") || exit 0
    # There is no exit after this point
fi

echo "Factory server is $serverIP. Setting $pionicIP as the default route"
ip route default via $pionicIP metric 1 || true

# XXX get the build ID here. This is a platform-specific operation. The build ID
# must uniquely identify the software build and the DUT device type. Note it
# must be entered into the server build data to determine which diagnostic
# tarball is sent to the DUT, therefore the build ID has to be predictable.
buildID=test

# XXX get the device ID from permanent storage here. This is a platform-specific
# operation. If device ID is not currently programmed then leave as "" and the
# system will scan the barcode from the PCB and then perform phase 1 tests
# which must include installation of the device ID.
deviceID=""

# XXX create a work directory. This is a platform-specific operation. The work
# directory must not survive reboot, if necessary mount a ramdisk/tmpfs and cd
# to that. Note it must be large enough to contain the contents of the
# diagnostic tarball. 256MB is a good target. The exact path doesn't matter.
echo "Creating work directory"
mkdir /tmp/diag
cd /tmp/diag

# Retrieve the diagnostic tarball from the server and unpack it into the
# current directory. Note we verify the https certificate public key is
# correct, so we can trust that the tarball really did come from the factory
# server and not from someone's laptop.
echo "Fetching tarball for build $buildID"
curl -qsSf -k --pinnedpubkey "sha256//$pubkey" --form-string "buildid=$buildID" "https://$server/cgi-bin/factory?service=download" | tar -xzv || die "Tarball download failed"

# The tarball must contain the dodiag script
[ -x ./dodiag ] || die "dodiag script is missing"

# Invoke dodiag, it will usually exit with 0 on success or non-zero on error
# But either way we spin forever since there is no safe exit from diagnostic mode.
./dodiag -p $pionicIP -s $serverIP $buildID $deviceID
die "dodiag exit with status $?"
