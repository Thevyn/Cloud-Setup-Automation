#! /bin/bash

PARAM_FILE=$1
source $PARAM_FILE



#IPs of databases and dbProxy
dbIp1=(${vmips[$(echo ${vmnames[@]/$projName-db-1//} | cut -d/ -f1 | wc -w | tr -d ' ')]})
dbIp2=(${vmips[$(echo ${vmnames[@]/$projName-db-2//} | cut -d/ -f1 | wc -w | tr -d ' ')]})
dbIp3=(${vmips[$(echo ${vmnames[@]/$projName-db-3//} | cut -d/ -f1 | wc -w | tr -d ' ')]})
dbProxyIp=(${vmips[$(echo ${vmnames[@]/$projName-db-proxy//} | cut -d/ -f1 | wc -w | tr -d ' ')]})


db1="
[srv1]
type = server
address = $dbIp1
port = 3306
protocol = MariaDBBackend
serv_weight = 1
"

db2="
[srv2]
type = server
address = $dbIp2
port = 3306
protocol = MariaDBBackend
serv_weight = 1
"

db3="
[srv3]
type = server
address = $dbIp3
port = 3306
protocol = MariaDBBackend
serv_weight = 1
"

#Make a string of the databases for galera. If db3 exists, it adds it too.
dbList="srv1,srv2"
if [ ! -z $dbIp3 ]
then
	dbList+=",srv3"
fi

galeraSetup="
[galera]
binlog_format=ROW
default-storage-engine=innodb
innodb_autoinc_lock_mode=2
bind-address=0.0.0.0
# GaleraProvider Configuration
wsrep_on=ON
wsrep_provider=/usr/lib/galera/libgalera_smm.so
# GaleraCluster Configuration
wsrep_cluster_address=gcomm://$projName-db-1,$projName-db-2
# GaleraSynchronization Configuration
wsrep_sst_method=rsync
"



if [ ! -z $dbIp3 ]
then
	galeraSetup=$(echo "$galeraSetup" | sed "s;$projName-db-1,$projName-db-2;$projName-db-1,$projName-db-2,$projName-db-3;")
fi


for idx in ${!vmnames[@]}; do
	if [[ ${vmnames[$idx]} == *"db-proxy"* ]]
	then
		ssh -i $sshKeyName ubuntu@${vmips[$idx]} "sudo sh -c 'cp /etc/maxscale.cnf.template /etc/maxscale.cnf' && sudo chmod 777 /etc/maxscale.cnf && sudo echo '$db1' | sudo bash -c 'cat >> /etc/maxscale.cnf' && sudo echo '$db2' | sudo bash -c 'cat >> /etc/maxscale.cnf' && sudo sed -i 's/auto/4/g' /etc/maxscale.cnf && sudo sed -i 's/MariaDB-Monitor/Galera-Monitor/g' /etc/maxscale.cnf && sudo sed -i 's/mariadbmon/galeramon/g' /etc/maxscale.cnf && sudo sed -i 's/myuser/maxscaleuser/g' /etc/maxscale.cnf && sudo sed -i 's/myuser/maxscaleuser/g' /etc/maxscale.cnf && sudo sed -i 's/mypwd/maxscalepass/g' /etc/maxscale.cnf && sudo sed -i 's/MariaDBClient/MySQLClient/g' /etc/maxscale.cnf && sudo sed -i 's/^port=.*$/port=3306/' /etc/maxscale.cnf && sudo sed -i 's/servers=server1/servers=srv1,srv2/g' /etc/maxscale.cnf && sudo chmod 644 /etc/maxscale.cnf && sudo sed -i '/Read-Only-Listener/,+4 d' /etc/maxscale.cnf && sudo service maxscale start"
		if [ ! -z $dbIp3 ]
		then
			ssh -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" -i $sshKeyName ubuntu@${vmips[$idx]} "sudo echo '$db3' | sudo bash -c 'cat >> /etc/maxscale.cnf' && sudo sed -i 's/servers=srv1,srv2/servers=srv1,srv2,srv3/g' /etc/maxscale.cnf"
		fi
elif [[ ${vmnames[$idx]} == *"db"*  &&  ${vmnames[$idx]} != *"proxy"* ]]
	then
		ssh -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" -i $sshKeyName ubuntu@${vmips[$idx]} 'sudo mysql -u root -e "GRANT select on mysql.* to \"maxscaleuser\"@\"%\" IDENTIFIED BY \"maxscalepass\"; GRANT replication slave ON *.* TO \"maxscaleuser\"@\"%\"; GRANT replication client ON *.* TO \"maxscaleuser\"@\"%\"; GRANT show databases ON *.* TO \"maxscaleuser\"@\"%\"; flush privileges;"'

		ssh -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" -i $sshKeyName ubuntu@${vmips[$idx]} "sudo echo '$galeraSetup' | sudo bash -c 'cat >> /etc/mysql/my.cnf' && sudo sed -i '/^password = / s/$/ 03P8rdlknkXr1upf/' /etc/mysql/debian.cnf && sudo sed -i 's/root/debian-sys-maint/g' /etc/mysql/debian.cnf"
	fi
done


sudo ssh ubuntu@$dbIp1 -i $sshKeyName "sudo service mysql stop"
sudo ssh ubuntu@$dbIp2 -i $sshKeyName "sudo service mysql stop"
if [ ! -z "$dbIp3" ]
then
	sudo ssh ubuntu@$dbIp3 -i $sshKeyName "sudo service mysql stop"
fi

sudo ssh ubuntu@$dbIp1 -i $sshKeyName "sudo galera_new_cluster"
sudo ssh ubuntu@$dbIp2 -i $sshKeyName "sudo service mysql start"
if [ ! -z "$dbIp3" ]
then
        sudo ssh ubuntu@$dbIp3 -i $sshKeyName "sudo service mysql start"
fi

echo Done setting up!
