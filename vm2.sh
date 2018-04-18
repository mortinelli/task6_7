#! /bin/bash
source vm2.config

ifup $INTERNAL_IF
ifconfig $INTERNAL_IF $INT_IP

route add default gw $GW_IP
cp /etc/resolv.conf /etc/resolv.conf.bak
rm /etc/resolv.conf
echo "nameserver 8.8.8.8" > /etc/resolv.conf

# vlan config
apt-get update
apt-get install vlan -y -qq
modprobe 8021q
vconfig add $INTERNAL_IF $VLAN
ifup "$INTERNAL_IF.$VLAN"
ifconfig "$INTERNAL_IF.$VLAN" $APACHE_VLAN_IP

apt-get install apache2 -y -qq
cat /etc/apache2/ports.conf | sed -e "s/Listen 80/Listen $APACHE_VLAN_IP:80/" > /tmp/ports.conf
mv /tmp/ports.conf /etc/apache2/ports.conf
systemctl reload apache2
