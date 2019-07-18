#!/bin/sh -eu

# This script is part of published root and runs as early as possible during
# boot. Because it can't easily be changed it does the minimum work necessary
# to download a tarball from the factory server, then passes control to
# dodiag.sh from the tarball.

# This is the pionic controller's IP address
pionicIP=192.168.111.1  # pionic controller IP address

# This is the factory detction method. If the DUT has a pre-defined static IP
# address at the time that this script runs, then use 'http'. Otherwise use
# 'beacon' (pionic must also be configured to start the beacon server).
method=http

# If 'beacon', this is the network interface that attaches to the pionic
# controller. Not required for http since the network must already be up.
interface=

# If 'beacon', the IP address to apply to the interface after beacon is
# detected (in the same subnet as pionic). Not required for http since the
# network must already be up.
localIP=

# The factory server has a self-signed https certificate. We verify the cert
# using the base-64 encoded sha256 of the public key. For reference, this can
# be obtained from the server with:
#
#   openssl s_client -connect X.X.X.X:443 </dev/null 2>/dev/null | openssl x509 -pubkey -noout | sed '/----/d' | base64 -d -w0 | openssl dgst -sha256 -binary | base64
#
# PLEASE NOTE there are two server certs. The development cert is insecure and
# must never be used in production. Production servers use a secret production
# cert, add its hash below once it's been defined.
#
# The production cert MUST remain secret, and the development hash MUST NOT be
# supported in production or your systems WILL BE HACKABLE.
#
# You have two options:
#
#   A) conditionally define the development hash below if you can unambiguously
#   detect development code or development hardware at this point in the boot.
#   You will be able to test development builds against development and
#   production servers. However you will not be able to test production builds
#   against development servers.
#
#   B) delete the development hash entirely once the production cert is
#   defined, and deploy the production cert to development servers. You will be
#   able to test any build against any server, however there is an increased
#   chance that the production cert will leak.

development="paYQewbP520iAv1hIi/A1lvYyVzMdDv6yEmp9El0aPc="
production=""

# We assume it's not possible to properly recover from diagnostic mode without
# a full reboot, therefore this script spins forever on any non-zero exit
# status.
trap '[ $? != 0 ] && while true; do echo "Reboot now"; sleep 5; done' EXIT

# die with message to stderr
die() { echo $* >&2; exit 1; }

# First, try to detect the factory.
if [ $method == beacon ]; then
    # Beacon mode, listen for an ethernet beacon. If we don't hear one then
    # assume we're not in the factory and just exit
    beacon recv 2 $interface pionic >/dev/null || exit 0
    # There is no exit after this point
    echo "Beacon detected, configuring $interface for $localIP"
    ip link set $interface up || true
    ip address add $localIP dev $interface || true
    echo "Fetching server IP from pionic"
    serverIP=$(curl -qsf -m3  "http://$pionicIP/factory") || die "Failed"
else
    # http mode, we assume $pionicIP is on the local subnet. Ask it for the
    # factory IP address, if it fails then assume we're not in the factory and
    # just exit.
    serverIP=$(curl -qsf -m3  "http://$pionicIP/factory") || exit 0
    # There is no exit after this point
fi

echo "Factory server is $serverIP"
# XXX set $pionicIP as default gateway if necessary

# XXX set the build ID. The build ID must uniquely identify the software build
# and the DUT device type. Note the server associates the buildID with a
# specific tarball containing the diagnostic code, therefore the buildID string
# must be predictable and human-writable.
buildID=test
echo "Using buildID $buildID"

# XXX create a work directory. The work directory must not survive reboot, if
# necessary mount a ramdisk/tmpfs and cd to that. Note the directory must be
# large enough to contain the contents of the diagnostic tarball. 256MB is a
# good target. The exact path doesn't matter.
echo "Creating work directory"
mkdir /tmp/diag
cd /tmp/diag

# Retrieve the diagnostic tarball from the server and unpack it into the
# current directory. Note we verify the hash of the https certificate public
# key, so we can trust that the tarball really did come from the factory server
# and not from someone's laptop. If both hashes are defined, try the production
# hash first. The development hash MUST NOT be defined for production software,
# see the note above.
for pubkey in ${production:-} ${development:-}; do
    echo "Downloading with key hash $pubkey"
    if curl -qsSf -k --pinnedpubkey "sha256//$pubkey" --form-string "buildid=$buildID" "https://$server/cgi-bin/factory?service=download" | tar -xzv; then
        # Success!
        [ -x ./dodiag.sh ] || die "Tarball does not contain dodiag.sh"
        # invoke with various parameters of interest
        ./dodiag.sh $pionicIP $serverIP $buildID
        die "dodiag.sh exit with status $?"
    fi
done
die "Tarball download failed"
