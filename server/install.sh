#!/bin/bash -eu

die() { echo $* >&2; exit 1; }
((!UID)) || die "Must be root"

(($# == 2)) || die "Usage: $0 factory_interface dut_interface"

factory_interface=$1
[[ -e /sys/class/net/$factory_interface ]] || die "Invalid network interface $factory_interface"
[[ $(cat /sys/class/net/$factory_interface) == 1 ]] || die "$factory_interface must be connected!"

dut_interface=$2
[[ -e /sys/class/net/$dut_interface ]] || die "Invalid network interface $dut_interface"
[[ $(cat /sys/class/net/$dut_interface) == 0 ]]  || die "$dut_interface must not be connected!"

# install packages
apt update
apt upgrade
apt install apache2 arping curl elinks htop iptables-persistent mlocate
apt install net-tools postgresql psmisc python-psycogreen sysstat tcpdump
apt install tmux vim
apt install --no-install-recommends dnsmasq

# copy files from directory containing this script to the same paths in the root
here=${0%/*}
for file in $(find $here -mindepth 2 \( -type f -o -type l \) -printf "%P\n"); do
    [[ -d /${file%/*} ]] || mkdir -v -p /${file%/*}
    cp -v -P -b $here/$file /$file          
done

# fix factory config
sed -i "s/FFFF/$factory_interface/g; s/DDDD/$dut_interface/g" /etc/factory/config

# configure DUT interface
sed -i "/DDDD/$dut_interface/g" /etc/network/interfaces.d/factory.conf
ifup $dut_interface

# fix factory permissions
chown -R factory: ~factory/
chmod -R go= ~factory/.ssh

# configure postgresql
su -lc "psql -f /etc/factory/schema.txt" postgrqs

# configure Apache
a2enmod cgi
a2enmod ssl
a2ensite default-ssl

# configure iptables
/etc/factory/iptables.sh

# configure dnsmasq
/etc/factory/config.dnsmasq

echo "Installation complete"
