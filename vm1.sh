#! /bin/bash
source vm1.config

# config EXTERNAL_IF
ifup $EXTERNAL_IF
if [[ $EXT_IP = *"DHCP"* ]]; then
dhclient $EXTERNAL_IF
else
ifconfig $EXTERNAL_IF $EXT_IP
route add default gw $EXT_GW
rm /run/resolvconf/resolv.conf
echo "nameserver 8.8.8.8" > /run/resolvconf/resolv.conf
fi

#config INTERNAL_IF
ifup $INTERNAL_IF
ifconfig $INTERNAL_IF $INT_IP

# Nat config and routing
echo 1 > /proc/sys/net/ipv4/ip_forward
iptables --flush
iptables --table nat --flush
iptables --delete-chain
iptables --table nat --delete-chain
iptables --table nat --append POSTROUTING --out-interface $EXTERNAL_IF -j MASQUERADE
iptables --append FORWARD --in-interface $INTERNAL_IF -j ACCEPT
service ufw restart

# vlan config
apt-get update
apt-get install vlan -y -qq
modprobe 8021q
vconfig add $INTERNAL_IF $VLAN
ifup "$INTERNAL_IF.$VLAN"
ifconfig "$INTERNAL_IF.$VLAN" $VLAN_IP

# external ip

curent_extip=$(ifconfig enp0s3 | grep "inet addr" | cut -d ':' -f 2 | cut -d ' ' -f 1)


# ngnix config

apt-get install nginx -y -qq

# sertificates

apt-get install openssl -y -qq

openssl genrsa -out root-ca.key 4096
openssl req -new -key root-ca.key -days 365 -nodes -x509 \
    -subj "/C=UA/ST=Kharvovskaya obl./L=Kharkov/O=Mirantis Matveev/CN=RootCA" \
    -out /etc/ssl/certs/root-ca.crt

curdir=$(pwd)
openssl genrsa -out vm1.key 4096

openssl req -new -key vm1.key \
    -subj "/C=UA/ST=Kharvovskaya obl./L=Kharkov/O=Mirantis Matveev/CN=vm1" \
    -reqexts SAN \
    -config <(cat /etc/ssl/openssl.cnf \
        <(printf "\n[SAN]\nsubjectAltName=IP:$curent_extip")) \
    -out vm1.csr


openssl x509 -req -extfile <(printf "subjectAltName=IP:$curent_extip") \
        -days 365\
        -CA /etc/ssl/certs/root-ca.crt \
        -CAkey root-ca.key -CAcreateserial \
        -in vm1.csr\
        -out /etc/ssl/certs/web.crt

cat /etc/ssl/certs/root-ca.crt >> /etc/ssl/certs/web.crt

#ngnix config


nconf="user www-data;\n
worker_processes auto;\n
pid /run/nginx.pid;\n

events {\n
\t\t        worker_connections 768;\n
}\n

http {\n
\t\t        default_type application/octet-stream;\n
\n
\t\t        # enable reverse proxy\n
\t    proxy_redirect              off;\n
\t    proxy_set_header            Host           \$http_host;\n
\t    proxy_set_header            X-Real-IP      \$remote_addr;\n
\t    proxy_set_header            X-Forwared-For \$proxy_add_x_forwarded_for;\n
\n
\t    upstream streaming_example_com\n
\t    {\n
\t\t          server $curent_extip:$NGINX_PORT;\n
\t    }\n
\n
 server\n
\t    {\n
\t\t        listen      $NGINX_PORT default ssl;\n
\t\t        server_name $APACHE_VLAN_IP;\n
\t\t        access_log  /tmp/nginx_reverse_access.log;\n
\t\t        error_log   /tmp/nginx_reverse_error.log;\n
\t\t        ssl_session_cache    shared:SSL:1m;\n
\t\t        ssl_session_timeout  10m;\n
\t\t        ssl_certificate /etc/ssl/certs/web.crt;\n
\t\t        ssl_certificate_key $curdir/vm1.key;\n
\t\t        ssl_verify_client off;\n
\t\t        ssl_protocols        SSLv3 TLSv1 TLSv1.1 TLSv1.2;\n
\t\t        ssl_ciphers RC4:HIGH:!aNULL:!MD5;\n
\t\t        ssl_prefer_server_ciphers on;\n
\n
\n
\t\t        location /\n
\t\t        {\n
\t\t            proxy_pass http://$APACHE_VLAN_IP;\n
\t\t        }\n
\t    }\n
}
"

cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
rm /etc/nginx/nginx.conf
echo -e $nconf > /etc/nginx/nginx.conf
systemctl reload nginx
