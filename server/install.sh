#!/bin/bash -eu

die() { echo $* >&2; exit 1; }
((!UID)) || die "Must be root"

# read the config file
here=${0%/*}
source $here/install.cfg

# make sure correct interfaces are defined
[[ -e /sys/class/net/$factory_interface ]] || die "Invalid network interface $factory_interface"
(($(cat /sys/class/net/$factory_interface/carrier 2>/dev/null))) || die "$factory_interface must be connected!"

[[ -e /sys/class/net/$dut_interface ]] || die "Invalid network interface $dut_interface"
! (($(cat /sys/class/net/$dut_interface/carrier 2>/dev/null))) || die "$dut_interface must not be connected!"

# install packages
export DEBIAN_FRONTEND=noninteractive
apt update
apt upgrade
apt install -y apache2 arping curl dnsmasq elinks htop iptables-persistent mlocate net-tools postgresql psmisc python-psycogreen smartmontools sudo sysstat tcpdump tmux vim

# copy files from overlay to root, make directories if needed, leave symlinks
# intact
for file in $(find $here/overlay -type f,l -printf "%P\n"); do
    [[ -d /${file%/*} ]] || mkdir -v -p /${file%/*}
    cp -v -P -b $here/overlay/$file /$file
done

# remember certain config
cat <<EOT >>/etc/factory/config
# this is a generated file, do no edit!
factory_interface=$factory_interface
dut_interface=$dut_interface
dut_ip=$dut_ip
EOT

# patch configurations
for f in /etc/network/interfaces.d/factory.conf /etc/ssh/ssh_config; do
    sed -i "s/FACTIF/$factory_interface/g; s/DUTIF/$dut_interface/g; s/DUTIP/$dut_ip/g; s/DUTNET/${dut_ip%.*}.*/g" $f
done

# shows at login prompt
cat <<EOT > /etc/issue
\e{bold}\d \t
Property of $organization
Unauthorized access is prohibited
$factory_interface address is \4{$factory_interface} (factory interface)
$dut_interface address is \4{$dut_interface} (DUT interface)
\e{reset}
EOT

# shows after login
cat <<EOT > /etc/motd
Property of $organization
Unauthorized access is prohibited
EOT

# fix factory permissions
chown -R factory: ~factory/
chmod -R go= ~factory/.ssh
chown root:factory /var/www/html/downloads
chmod 775 /var/www/html/downloads

# configure postgresql
su -lc "psql -f /etc/factory/schema.txt" postgres

# configure Apache
a2enmod cgi
a2enmod ssl
a2ensite default-ssl

# configure dnsmasq
ifup $dut_interface
/etc/factory/update.dnsmasq

# force UCT
ln -sf /usr/share/zoneinfo/UCT /etc/localtime

# configure iptables
iptables -F # flush everything
iptables -X # delete user chains
iptables -Z # zero counters

# trust lo
iptables -A INPUT -i lo -j ACCEPT

# allow expected
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

# https
iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# ssh
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# http for DUTs
iptables -A INPUT -i $dut_interface -p tcp --dport 80 -j ACCEPT

# dhcp for the DUTs
iptables -A INPUT -i $dut_interface -p udp --dport 67 -j ACCEPT

# dns for the DUTs
iptables -A INPUT -i $dut_interface -p udp --dport 53 -j ACCEPT
iptables -A INPUT -i $dut_interface -p tcp --dport 53 -j ACCEPT

# NAT forward DUTs
iptables -t nat -A POSTROUTING -o $factory_interface -j MASQUERADE

# drop all other inputs
iptables -P INPUT DROP

# save for boot script
iptables-save > /etc/iptables/rules.v4

# disable ipv6
ip6tables -F # flush everything
ip6tables -P INPUT DROP
ip6tables-save > /etc/iptables/rules.v6

echo "######################"
echo "Installation complete!"
