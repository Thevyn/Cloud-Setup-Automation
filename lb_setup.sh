#! /bin/bash

PARAM_FILE=$1
source $PARAM_FILE



#This is the config that should be added to the end of/etc/haproxy/haproxy.cnf
conf="frontend myfrontend
	bind *:80 
	mode http
	default_backend mybackend
backend mybackend 
	mode http
	balanse roundrobin
	option httpchk HEAD / HTTP/1.1\r\nHost:\ localhost
	server web1 $projName-web-1 check weight 10
	server web2 $projName-web-2 check weight 10
	server web3 $projName-web-3 check weight 10

	stats enable
	stats show-node
	stats show-legends
	stats refresh 30s
	stats uri /stats
	stats realm Haproxy\ Statistics
	stats hide-version
	stats auth dats37:rose rose ring
	stats admin if TRUE"

#Command to be sent to enable haproxy by grepping 'ENABLED' and then changing the ENABLED=1 by using sed
#enablyProxy='sudo bash -c "grep -q ENABLED= /etc/default/haproxy && sudo sed -i '/ENABLED=/c\ENABLED=1' /etc/default/haproxy || sudo sed -i '$ a ENABLED=1' /etc/default/haproxy"'

haproxy="/etc/haproxy/haproxy.cfg"
for idx in ${!vmnames[@]}; do
	if [[ ${vmnames[$idx]} == *"lb"* ]]
	then
        #ssh to the load balancer vm instance and then run the commands to enable haproxy and write the config file to haproxy.cfg
		ssh -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" -i $sshKeyName ubuntu@${vmips[$idx]} "grep -q ENABLED= /etc/default/haproxy && sudo sed -i '/ENABLED=/c\ENABLED=1' /etc/default/haproxy || sudo sed -i '$ a ENABLED=1' /etc/default/haproxy && sudo echo '$conf' | sudo bash -c 'cat > $haproxy'"


	fi
done
