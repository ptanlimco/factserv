#!/bin/bash -eu

# Edit iptables configure here then run to make permanent
# We assume that iptables-persistent package is installed

source /etc/factory.cfg

# reset
iptables -F # flush everything
iptables -X # delete user chains
iptables -Z # zero counters

ip6tables -F # flush everything
ip6tables -X # delete user chains
ip6tables -Z # zero counters

# trust lo
iptables -A INPUT -i lo -j ACCEPT

# allow expected
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

# dhcp on eno2
iptables -A INPUT -i $dut_interface -p udp --dport 67 -j ACCEPT

# ssh
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# dns on eno2
iptables -A INPUT -i $dut_interface -p udp --dport 53 -j ACCEPT
iptables -A INPUT -i $dut_interface -p tcp --dport 53 -j ACCEPT

# NAT forward (comment this out in production?)
iptables -t nat -A POSTROUTING -o $factory_interface -j MASQUERADE

# drop all other inputs
iptables -P INPUT DROP
ip6tables -P INPUT DROP

# save for boot script
iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6
