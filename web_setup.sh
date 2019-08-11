#! /bin/bash
#Parameterized scripts which uses the variables in params.sh
PARAM_FILE=$1
source $PARAM_FILE


#Function to return the nginx server config file to not hardcode each server_name ip to make sure PHP request is processed by using php-fmp
function serverfile {
  #A variable which is what should be replaced inside nginx config file /etc/nginx/sites-available/default'   
  server_file="server {
        listen 80 default_server;
        listen [::]:80 default_server;
        
        root /var/www/html;
        index index.php index.html index.htm index.nginx-debian.html;
        server_name $1;

        location / {
                try_files \$uri \$uri/ =404;
        }

        location ~ \.php$ {     
                include snippets/fastcgi-php.conf;
                fastcgi_pass unix:/run/php/php7.0-fpm.sock;
        }
        location ~ /\.ht {
                deny all;
                }
        }"   

    #Since bash function cannot return strings, we echo it out to store it in a another variable
   echo "$server_file"
    
}



#Crontab setup variable which should be added to the crontab file to automatically rsync from web server 1
crontab1='(crontab -l 2>/dev/null ; echo "*/2 * * * * rsync -avz --delete -e \"ssh -o \"UserKnownHostsFile=/dev/null\" -o \"StrictHostKeyChecking=no\" -i  '$sshKeyName'\"  /var/www/html/* ubuntu@'$projName-web-2':/var/www/html/") | crontab -'
crontab2='(crontab -l 2>/dev/null ; echo "*/2 * * * * rsync -avz --delete -e \"ssh -o \"UserKnownHostsFile=/dev/null\" -o \"StrictHostKeyChecking=no\" -i  '$sshKeyName'\"  /var/www/html/* ubuntu@'$projName-web-3':/var/www/html/") | crontab -'
#Automatically change the rights to nginx web folders and make sure ubuntu has the correct permissions
changeRights="sudo adduser ubuntu www-data && sudo chown -R www-data:www-data /var/www  && sudo chmod -R g+rw /var/www"
#Loop through all the vms in the project
for idx in ${!vmnames[@]}; do
	#If statement to check if the VM instance is a web server
        if [[ ${vmnames[$idx]} == *"web"* ]]
        then
	#asign server_file variable the nginx config file with the correct server_name for each web server by calling the function serverfile with a parameter to the server name which should be used. So that we don't hardcode the IPs but use the hostname in /etc/hosts
	server_file=$(serverfile ${vmnames[$idx]})
	#ssh into the different web servers and Execute changeRight command and write the server config file to the web server and then restart nginx to apply these changes. 
	ssh -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" -i $sshKeyName ubuntu@${vmips[$idx]} "$changeRights && sudo echo '$server_file' | sudo bash -c 'cat  > /etc/nginx/sites-available/default' && sudo service nginx restart"  
        fi
	#Another If statement to only add crontab setup to web server 2-3
	if [[ ${vmnames[$idx]} == *"web-1"* ]] 
		then
    
   sudo scp -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" -i $sshKeyName $sshKeyName ubuntu@${vmips[$idx]}:~ 
   ssh -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" -i $sshKeyName ubuntu@${vmips[$idx]} "$crontab1 && $crontab2"
    fi
done

