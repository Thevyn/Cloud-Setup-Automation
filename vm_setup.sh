#! /bin/bash

source ~/dats37-openrc.sh
PARAM_FILE=$1
source $PARAM_FILE

#Generating ssh-key
ssh-keygen -t rsa -f $sshKeyName
openstack keypair create --public-key $sshKeyName.pub $sshKeyName

#CREATE SECURITY GROUP

echo 'Creating security group'
openstack security group create $secName

echo 'Creating security rule'
openstack security group rule create --proto tcp --src-ip 0.0.0.0/0 --dst-port 22 $secName
openstack security group rule create --proto tcp --src-ip 0.0.0.0/0 --dst-port 80 $secName
openstack security group rule create --proto tcp --src-ip 0.0.0.0/0 --dst-port 3306 $secName
openstack security group rule create --proto tcp --src-ip 0.0.0.0/0 --dst-port 4567 $secName
openstack security group rule create --proto tcp --src-ip 0.0.0.0/0 --dst-port 4568 $secName
openstack security group rule create --proto tcp --src-ip 0.0.0.0/0 --dst-port 4444 $secName

#CREATE VMs

echo "creating VMs"

#midlertidig tar kun to WEB og to DB. Endre --max til 3 for disse etter testing.

#Functions for creating VMs.
#It checks for errors and recreates the VMs until they are successfully started.
#*Status is empty if the VM is not active. *Exist is empty if the VM doesnt exist.

function lb {
    lbStatus=($(openstack server list | grep $projName-lb | grep ACTIVE))
    if [[ -z $lbStatus ]] 
    then
        lbExist=($(openstack server list | grep $projName-lb))
        if [[ ! -z $lbExist ]]
        then 
            openstack server delete $projName-lb
        fi
        openstack server create --image 'Ubuntu16.04' --flavor m1.1GB --nic net-id=BSc_dats_network --security-group $secName --key-name $sshKeyName --min 1 --wait $projName-lb
        lb
    fi
}

function web {
    webStatus=($(openstack server list | grep $projName-web | grep ACTIVE))
    if [[ -z $webStatus ]]
    then
        webExist=($(openstack server list | grep $projName-web))
        if [[ ! -z $webExist ]]
        then
            openstack server delete $projName-web-1
            openstack server delete $projName-web-2
            openstack server delete $projName-web-3
        fi
        openstack server create --image 'Ubuntu16.04' --flavor m1.512MB4GB --nic net-id=BSc_dats_network --security-group $secName --key-name $sshKeyName --min 1 --max 3 --wait $projName-web
        web
    fi
}

function db {
    dbStatus=($(openstack server list | grep $projName-db | grep ACTIVE)) 
    if [[ -z $dbStatus ]] 
    then
        dbExist=($(openstack server list | grep $projName-db))
        if [[ ! -z $dbExist ]]
        then
            openstack server delete $projName-db-1
            openstack server delete $projName-db-2
            openstack server delete $projName-db-3
        fi
        openstack server create --image 'Ubuntu16.04' --flavor m1.512MB4GB --nic net-id=BSc_dats_network --security-group $secName --key-name $sshKeyName --min 1 --max 3 --wait $projName-db
        db
    fi
}

function db-proxy {
    dbProxyStatus=($(openstack server list | grep $projName-db-proxy | grep ACTIVE))
    if [[ -z $dbProxyStatus ]]
    then
        dbProxyExist=($(openstack server list | grep $projName-db-proxy))
        if [[ ! -z $dbProxyExist ]]
        then
            openstack server delete $projName-db-proxy
        fi
        openstack server create --image 'Ubuntu16.04' --flavor m1.512MB4GB --nic net-id=BSc_dats_network --security-group $secName --key-name $sshKeyName --min 1 --max 1 --wait $projName-db-proxy
        db-proxy
    fi
}

lb
web
db
db-proxy


#Wait 10 seconds to ensure that every VM is ready for ssh.
sleep 10
#Array of VM names
vmnames=($(openstack server list --name $projName -c Name | awk '!/^$|Name/ {print $2;}'))
#Array of VM IPs
vmips=($(openstack server list --name $projName -c Networks | awk '1' RS="[^0-9.]+"))
#CONFIGURING THE VMs
echo "Configuring the VMs"


echo adding /etc/hosts and updates the VMs
for i in ${!vmips[@]}; do
	ipList="${vmips[$i]} ${vmnames[$i]} \n$ipList"
done

for idx in ${!vmnames[@]}; do
	name=${vmnames[$idx]}
	ip=${vmips[$idx]}
	pip=$(openstack server show $name | grep -o "$pipsubnet\.[0-9]*\.[0-9]*")


	ssh -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" -i $sshKeyName ubuntu@$ip "sudo sh -c 'echo $name > /etc/hostname' && sudo bash -c 'echo " LANGUAGE='$mylocale' LC_ALL='$mylocale' " >> /etc/default/locale' && sudo echo -e '$ipList' | sudo bash -c 'cat >> /etc/hosts' && sudo apt-get update"

	if [[ $name == *"lb"* ]] 
	then
		echo Configuring lb
		ssh -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" -i $sshKeyName ubuntu@$ip "sudo DEBIAN_FRONTEND=noninteractive apt install -y haproxy"
    fi
    if [[ $name == *"web"* ]] 
    then
		echo Configuring web
		ssh -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" -i $sshKeyName ubuntu@$ip "sudo DEBIAN_FRONTEND=noninteractive apt install -y nginx && sudo DEBIAN_FRONTEND=noninteractive apt install -y php && sudo DEBIAN_FRONTEND=noninteractive apt install -y php-fpm"
    fi
	if [[ $name == *"db-proxy"* ]] 
	then
		echo Configuring db-proxy
        ssh -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" -i $sshKeyName ubuntu@$ip "sudo DEBIAN_FRONTEND=noninteractive apt install -y mariadb-client && sudo wget https://downloads.mariadb.com/MaxScale/2.2.2/ubuntu/dists/xenial/main/binary-amd64/maxscale-2.2.2-1.ubuntu.xenial.x86_64.deb && sudo dpkg -i maxscale-2.2.2-1.ubuntu.xenial.x86_64.deb && sudo apt-get -f install -qq"
    fi
    if [[ $name == *"db"* && $name != *"db-proxy"*  ]]
	then
		echo Configuring db
                ssh -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" -i $sshKeyName ubuntu@$ip "sudo apt-get install -y software-properties-common && sudo apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xF1656F24C74CD1D8 && sudo add-apt-repository 'deb [arch=amd64,arm64,i386,ppc64el] http://mirror.homelab.no/mariadb/repo/10.2/ubuntu xenial main' && sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt install -y mariadb-server"
	fi

done

exit
