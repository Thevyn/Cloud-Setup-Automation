#Project name
projName="test19-proj"
#SSH key name
sshKeyName="test19-key"
#Security group name
secName="test19-sg"
#Array of VM names
vmnames=($(openstack server list --name $projName -c Name | awk '!/^$|Name/ {print $2;}'))
#Array of VM IPs
vmips=($(openstack server list --name $projName -c Networks | awk '1' RS="[^0-9.]+"))
#Subnet ip
pipsubnet="10\.10"
