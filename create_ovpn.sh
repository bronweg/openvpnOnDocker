#!/bin/bash

#External IP of the VPN machine.
vpn_server_address=1.2.3.4

#Local path for ovpn generated configuration.
path_to_save_openvpn_config="/root/ovpn"

#That password going to be used as cert and key passfrases.
mainPassword="P@ssw0rD"

#The CN of the certificate.
commonName=$(hostname)

#Local path where users ovpn files will be generated (can be relative to ${path_to_save_openvpn_config}).
usersFolder="users"

#Address of the local network. On client machine packets to this network will be redirected to VPN.
networkAddress="192.168.1.0"

#IP address of the DNS server, going to be set as DNS server on client machine for whole VPN session time.
#dnsAddress=

#Going to be set as 'search' domain on client machine for whole VPN session time.
#domainName=

if [[ $(id -u) -ne 0 ]]; then
echo "This script has to be run as root user"
exit 1
fi

checkStatus() {
status=$?
placeOfFall=$1
test $status -ne 0 && echo "Error occured, status was $status, failed on $placeOfFall" && exit 1
}

test -z $vpn_server_address && echo -e "ERROR!\nvpn_server_address is missing" && exit 1
test -z $path_to_save_openvpn_config && echo -e "ERROR!\npath_to_save_openvpn_config is missing" && exit 1
test -z $mainPassword && echo -e "ERROR!\nmainPassword is missing" && exit 1
test -z $commonName && echo -e "ERROR!\ncommonName is missing" && exit 1
test -z $usersFolder && echo -e "ERROR!\nusersFolder is missing" && exit 1
test -z $networkAddress && echo -e "ERROR!\nnetworkAddress is missing" && exit 1

which expect >/dev/null || yum install -y expect || apt-get install -y expect
checkStatus 1

which dos2unix >/dev/null || yum install -y dos2unix || apt-get install -y dos2unix
checkStatus 2

which docker-compose >/dev/null || ( \
curl -L "https://github.com/docker/compose/releases/download/1.24.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && \
checkStatus 3 &&\
chmod +x /usr/local/bin/docker-compose )

mkdir ${path_to_save_openvpn_config}
checkStatus 4

cat << EOF >> ${path_to_save_openvpn_config}/docker-compose.yml
version: '2'  
services:  
  openvpn:
    cap_add:
     - NET_ADMIN
    image: kylemanna/openvpn
    container_name: openvpn
    ports:
     - "1194:1194/udp"
    restart: always
    volumes:
     - ${path_to_save_openvpn_config}:/etc/openvpn
EOF
checkStatus 5

cat << EOF >> ${path_to_save_openvpn_config}/expect_ovpn_initpki.sh
#!$(which expect) -f
set timeout -1
spawn docker-compose run --rm openvpn ovpn_initpki
expect "Enter New CA Key Passphrase:"
send "${mainPassword}\r"
expect "Re-Enter New CA Key Passphrase:"
send "${mainPassword}\r"
expect "Common Name *:"
send "${commonName}\r"
expect "Enter pass phrase for /etc/openvpn/pki/private/ca.key:"
send "${mainPassword}\r"
expect "Enter pass phrase for /etc/openvpn/pki/private/ca.key:"
send "${mainPassword}\r"
expect "CRL file: *"
send "exit\r"
EOF
checkStatus 6
chmod +x ${path_to_save_openvpn_config}/expect_ovpn_initpki.sh

cd ${path_to_save_openvpn_config}

docker-compose run --rm openvpn ovpn_genconfig -u udp://${vpn_server_address}
wait $!
checkStatus 7
./expect_ovpn_initpki.sh
checkStatus 8

docker-compose up -d openvpn
checkStatus 9

mkdir ${usersFolder}
checkStatus 10

cat << EOF >> create_user.sh
#!/bin/bash

client_name=\${1:-user}
mainPassword='${mainPassword}'
usersFolder=${usersFolder}
networkAddress=${networkAddress}
dnsAddress=${dnsAddress:-8.8.8.8}
domainName=${domainName:-example.com}

expect -c "spawn docker-compose run --rm openvpn easyrsa build-client-full \${client_name} nopass; expect \"Enter pass phrase for *:\"; send \"\${mainPassword}\r\"; expect \"Data Base Updated\"; send \"exit\r\""
docker-compose run --rm openvpn ovpn_getclient \${client_name} > \${usersFolder}/\${client_name}.ovpn

echo -ne "\
route-nopull \n\
route \${networkAddress} 255.255.255.0 \n\
dhcp-option DNS \${dnsAddress} \n\
dhcp-option DOMAIN \${domainName}" >> \${usersFolder}/\${client_name}.ovpn

sed -i "s/^redirect-gateway.*//" \${usersFolder}/\${client_name}.ovpn

dos2unix \${usersFolder}/\${client_name}.ovpn

EOF
checkStatus 11

chmod +x create_user.sh

#EOF
