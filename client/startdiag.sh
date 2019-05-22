#!/bin/sh -eu

# This runs immediately after network interfaces have been brought up.

# Try to talk to pionic server on gateway port 80. Normally the gateway will
# refuse the connection and we'll be done in a few milliseconds. But in the
# factory we'll get a response.
server=$(curl -qsf -m3  "http://192.168.111.1/factory") || exit 0

# Response gotten, this script will not exit
reason=
trap 'while true; do echo "${reason:-Unknown failure} - reboot now"; sleep 30; done' EXIT 
die() { reason=$*; exit 1; }

echo "Starting diags with factory server $server"

# XXX get the build ID here
buildID=test

# XXX get the device ID from flash here. If it's not programmed then leave as
# "" and the system will perform phase 1 testing, one of the phase 1 tests will
# program the device ID for next time.
deviceID=""

echo "Mounting tmpfs work directory"
mount -o tmpfs /mnt || die "Mount failed"
cd /mnt 

echo "Fetching tarball for build $buildID"
# note we use https and require the factory public key
curl -qsSf -k --pinnedpubkey "sha256//paYQewbP520iAv1hIi/A1lvYyVzMdDv6yEmp9El0aPc=" --form-string "buildid=$buildID" "https://$server/cgi-bin/factory?service=download" | tar -xzv || die "Tarball download failed"

# require the dodiags script
[ -x ./dodiag ] || die "dodiag script is missing"

# Invoke dodiag, it exits with status 1 on error, or 0 on success
./dodiag -s $server $buildID $deviceID || die "dodiag failed"

reason="dodiag success"
