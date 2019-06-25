#!/bin/bash -eu

die() { echo $* >&2; exit 1; }
((!UID)) || die "Must be root"

(($# >= 2)) || die "Usage: $0 factory_interface dut_interface [dut_ip]"

factif=$1
[[ -e /sys/class/net/$factif ]] || die "Invalid network interface $factif"
(($(cat /sys/class/net/$factif/carrier 2>/dev/null))) || die "$factif must be connected!"

dutif=$2
[[ -e /sys/class/net/$dutif ]] || die "Invalid network interface $dutif"
! (($(cat /sys/class/net/$dutif/carrier 2>/dev/null))) || die "$dutif must not be connected!"

dutip=${3:-172.16.240.254}

# install packages
apt update
apt upgrade
packages="apache2 arping curl elinks htop iptables-persistent mlocate net-tools postgresql psmisc python-psycogreen smartmontools sudo sysstat tcpdump tmux vim"
export DEBIAN_FRONTEND=noninteractive
apt install -y $packages
# we don't want resolvconf
apt install -y --no-install-recommends dnsmasq

# copy files from directory containing this script to the same paths in the root
here=${0%/*}
for file in $(find $here -mindepth 2 \( -type f -o -type l \) -printf "%P\n"); do
    [[ -d /${file%/*} ]] || mkdir -v -p /${file%/*}
    cp -v -P -b $here/$file /$file
done

# patch configuration files
for f in /etc/factory/config /etc/issue /etc/network/interfaces.d/factory.conf ~factory/.ssh/config; do
    sed -i "s/FACTIF/$factif/g; s/DUTIF/$dutif/g; s/DUTIP/$dutip/g; s/DUTNET/${dutip%.*}.*/g" $f
done

# fix factory permissions
chown -R factory: ~factory/
chmod -R go= ~factory/.ssh

# configure postgresql
su -lc "psql -f /etc/factory/schema.txt" postgres

# configure Apache
a2enmod cgi
a2enmod ssl
a2ensite default-ssl

# configure iptables
/etc/factory/iptables.sh

# configure dnsmasq
ifup $dutif
/etc/factory/update.dnsmasq

# change to UCT
ln -sf /usr/share/zoneinfo/UCT /etc/localtime

echo "######################"
echo "Installation complete!"
