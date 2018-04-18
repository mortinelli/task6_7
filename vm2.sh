#! /bin/bash

intif=$(cat vm2.config | grep "INTERNAL_IF=" | cut -d'"' -f2)
mngmtif=$(cat vm2.config | grep "MANAGEMENT_IF=" | cut -d'"' -f2)
vlan=$(cat vm2.config | grep  "VLAN=" | cut -d "=" -f2)
apvlanip=$(cat vm2.config | grep "APACHE_VLAN_IP=" | cut -d'=' -f2)
intip=$(cat vm2.config | grep "INT_IP=" | cut -d'=' -f2)
gw=$(cat vm2.config | grep "GW_IP" | cut -d'=' -f2)

ifup $intif
ifconfig $intif $intip

route add default gw $gw
cp /etc/resolv.conf /etc/resolv.conf.bak
rm /etc/resolv.conf
echo "nameserver 8.8.8.8" > /etc/resolv.conf

# vlan config
apt-get update
apt-get install vlan -y -qq
modprobe 8021q
vconfig add $intif $vlan
ifup "$intif.$vlan"
ifconfig "$intif.$vlan" $apvlanip

apt-get install apache2 -y -qq
cat /etc/apache2/ports.conf | sed -e "s/Listen 80/Listen $apvlanip:80/" > /tmp/ports.conf
mv /tmp/ports.conf /etc/apache2/ports.conf
systemctl reload apache2
