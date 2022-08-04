# Azure Monitor Demos

## Connection Monitor (WORK IN PROGRESS)

Based on:
- https://github.com/Danieleg82/AzureVPN-NAT
- https://github.com/Azure/Azure-vpn-config-samples/blob/master/Cisco/Current/ASR/Site-to-Site_VPN_using_Cisco_ASR.md

### Prerequisits
- ensure provider Microsoft.Insights is registered.


### Setup overview:

~~~ mermaid
classDiagram
vnetHub --> vnetOnPrem : vpn
vnetHub : cidr 10.1.0.0/16
gwHub --> vnetHub
gwHub: 10.1.0.4
gwHub: gwHub-pubIP
vmHub --> vnetHub
vmHub: 10.1.0.4
vmOnPrem --> vnetOnPrem
vmOnPrem: 172.16.0.5
vnetOnPrem : cidr 172.16.0.0/16
gwOnPrem --> vnetOnPrem
gwOnPrem: 172.16.0.4
gwOnPrem: gwOnPrem-pubIP
~~~

### Define variables:

~~~ bash
prefix=azcptdmon
location=eastus
myip=$(curl ifconfig.io) # Just in case we like to whitelist our own ip.
myobjectid=$(az ad user list --query '[?displayName==`ga`].id' -o tsv) # just in case we like to assing some RBAC roles to ourself.
~~~

### Agree to cisco terms if not already done.

~~~ bash
# find the right urn
az vm image list --all --publisher cisco --offer cisco-csr-1000v --query [].urn
# accept terms
az vm image terms accept --urn cisco:cisco-csr-1000v:17_2_1-byol:17.2.120200508
~~~

### Create foundation:

~~~ bash
# az group delete -n $prefix -y
az group create -n $prefix -l $location
az deployment group create -n $prefix -g $prefix --mode incremental --template-file deploy.bicep -p prefix=$prefix myobjectid=$myobjectid location=$location myip=$myip
~~~

### Verify VPN status (NotConnected)

VPN Connection status, expect "NotConnected":

~~~ bash
az network vpn-connection show -g $prefix -n ${prefix}hub --query '{name:name,connectionStatus:connectionStatus,egressBytesTransferred:egressBytesTransferred,ingressBytesTransferred:ingressBytesTransferred,tunnelConnectionStatus:tunnelConnectionStatus}'
~~~

Output:

~~~ json
{
  "connectionStatus": "NotConnected",
  "egressBytesTransferred": 0,
  "ingressBytesTransferred": 0,
  "name": "azcptdmonhub",
  "tunnelConnectionStatus": null
}
~~~

Ping from Cisco VM, expect Success rate is 0 percent (0/5):

~~~ bash
az network public-ip show -g $prefix -n ${prefix}opgw --query ipAddress -o tsv # 13.92.214.109
# log into cisco vm via bastion
vmopgwid=$(az vm show -g $prefix -n ${prefix}opgw --query id -o tsv)
az network bastion ssh -n ${prefix}op -g $prefix --target-resource-id $vmopgwid --auth-type password --username chpinoto
demo!pass123
ping 10.1.0.4 # Success rate is 0 percent (0/5)
logout
~~~

### Azure VGW VPN connection tcp dump (disconnected):

~~~ bash
vpnconid=$(az network vpn-connection show -g $prefix -n ${prefix}hub --query id -o tsv)
az network vpn-connection packet-capture start -n ${prefix}hub -g $prefix
# get sas-url
saep=$(az storage account show -n $prefix --query primaryEndpoints.blob -o tsv) # get <my>.blob.core.windows.net
sasexpire=`date -u -d "30 minutes" '+%Y-%m-%dT%H:%MZ'`
sastoken=$(az storage container generate-sas --account-name $prefix -n $prefix --permissions acdlrw --expiry $sasexpire --auth-mode login --as-user -o tsv)
sasurl=${saep}${prefix}?${sastoken}
# retrieve data
az network vpn-connection packet-capture stop -n ${prefix}hub -g $prefix --sas-url $sasurl
~~~

To get the logs you can either use:
- Use azure storage explorer
- azcopy

> IMPORTANT: In case you are runnin WSL, please not this will not work. You should run this outside of WSL.

~~~ powershell
az login
azcopy list https://azcptdmon.blob.core.windows.net/azcptdmon --output-type json | jq .
azcopy copy https://azcptdmon.blob.core.windows.net/azcptdmon/2022/8/4/05:54:45.2013121/armrg-c2890077-8a74-4b87-9b89-47ad0927c02b/13.92.214.109_Instance_GatewayTenantWorker_IN_1.pcap .
wireshark -r 13.92.214.109_Instance_GatewayTenantWorker_IN_1.pcap
azcopy remove https://azcptdmon.blob.core.windows.net/azcptdmon/2022/ --recursive=true
~~~

### Cisco VPN config

> IMPORTANT replace the current public ip of azure vgw vpn inside the cisco config before running this commands.

~~~ bash
az network public-ip show -g $prefix -n ${prefix}hub --query ipAddress -o tsv # 40.121.54.39
vmopgwid=$(az vm show -g $prefix -n ${prefix}opgw --query id -o tsv)
az network bastion ssh -n ${prefix}op -g $prefix --target-resource-id $vmopgwid --auth-type password --username chpinoto
demo!pass123

# start config
Conf t

crypto ikev2 proposal Azure-Ikev2-Proposal
encryption aes-cbc-256
integrity sha1 sha256
group 2
!
crypto ikev2 policy Azure-Ikev2-Policy
match address local 172.16.0.4
proposal Azure-Ikev2-Proposal
!
crypto ikev2 keyring to-onprem-keyring
peer 40.121.54.39
address 40.121.54.39
pre-shared-key demo!pass123
!
crypto ikev2 profile Azure-Ikev2-Profile
match address local 172.16.0.4
match identity remote address 40.121.54.39
authentication remote pre-share
authentication local pre-share
keyring local to-onprem-keyring
lifetime 28800
dpd 10 5 on-demand
!
crypto ipsec transform-set to-Azure-TransformSet esp-gcm 256
mode tunnel
!
crypto ipsec profile to-Azure-IPsecProfile
set transform-set to-Azure-TransformSet
set ikev2-profile Azure-Ikev2-Profile
!
interface Loopback1
ip address 192.168.1.1 255.255.255.255
!
interface Tunnel1
ip address 192.168.2.1 255.255.255.255
ip tcp adjust-mss 1350
tunnel source 172.16.0.4
tunnel mode ipsec ipv4
tunnel destination 40.121.54.39
tunnel protection ipsec profile to-Azure-IPsecProfile
!
router bgp 65001
bgp router-id 192.168.1.1
bgp log-neighbor-changes
neighbor 10.1.4.254 remote-as 65515
neighbor 10.1.4.254 ebgp-multihop 255
neighbor 10.1.4.254 update-source Loopback1
!
address-family ipv4
neighbor 10.1.4.254 activate
network 10.0.0.0 mask 255.0.0.0
exit-address-family
!
!Static route to Azure BGP peer IP
ip route 10.1.4.254 255.255.255.255 Tunnel1
!Static route to internal workload subnet
ip route 10.0.0.0 255.0.0.0 172.16.0.1
!

End
Wr

ping 10.1.0.4 # TODO Success rate is 0 percent (0/5), should be 100%
logout
~~~

### Test connection

~~~ mermaid
classDiagram
vmOnPrem<-->vmHub: Ping via VPN
vmHub: 10.1.0.4
vmOnPrem: 172.16.0.5
~~~

From onprem to hub

~~~ bash
# prefix=azcptdmon
vmopid=$(az vm show -g $prefix -n ${prefix}opvm --query id -o tsv)
az network bastion ssh -n ${prefix}op -g $prefix --target-resource-id $vmopid --auth-type password --username chpinoto
demo!pass123
ping 10.1.0.4 # expect 0% packet loss
logout
~~~

From hub to onprem

~~~ bash
prefix=azcptdmon
vmhubid=$(az vm show -g $prefix -n ${prefix}hubvm --query id -o tsv) # linked to pdns
az network bastion ssh -n ${prefix}hub -g $prefix --target-resource-id $vmhubid --auth-type password --username chpinoto
demo!pass123
ping 172.16.0.5 # expect 0% packet loss
logout
~~~

From spoke to cisco via hub.

~~~ bash
vmspokeid=$(az vm show -g $prefix -n ${prefix}spokevm --query id -o tsv) # linked to pdns
az network bastion ssh -n ${prefix}hub -g $prefix --target-resource-id $vmspokeid --auth-type password --username chpinoto
demo!pass123
ping 172.16.0.5 # expect 0% packet loss
logout
~~~

### Connection Manager

> NOTE: We expect that you already have an existing "Network Watch" Azure resource and a corresponding "Log Analytics Workspace" setup.

Create Azure connection-monitor ICMP test from:

~~~ mermaid
classDiagram
vmOnPrem-->vmHub: Ping via VPN
vmOnPrem-->vmSpoke: Ping via VPN
vmHub: 10.1.0.4
vmSpoke: 10.2.0.4
vmOnPrem: 172.16.0.5
~~~

Because this would become a very long az cli command we did put everything inside a bash script called azconmon.sh which can be feeded with the needed parameters.

Retrieve the Log Analytis Workspace id.

~~~ bash
lawguid=$(az monitor log-analytics workspace list -g $prefix --query [].customerId -o tsv)
lawid=$(az monitor log-analytics workspace show -g $prefix -n $prefix --query id -o tsv)
~~~

Create connection monitor test.

> NOTE: After all the changes which have been introduce you maybe will face issue by setting up the connnection monitor test. If this is the case just restart the VMs and it should work. At least it did work for me.

~~~ bash
vmopname=$(az vm show -g $prefix -n ${prefix}opvm --query name -o tsv)
vmhubname=$(az vm show -g $prefix -n ${prefix}hubvm --query name -o tsv)
vmspokename=$(az vm show -g $prefix -n ${prefix}spokevm --query name -o tsv)
azbicep/bicep/./azconmon.sh $prefix $location optohub $vmopid $vmopname $vmhubid $vmhubname
azbicep/bicep/./azconmon.sh $prefix $location optospoke $vmopid $vmopname $vmspokeid $vmspokename
~~~

Verify if test have been deployed.

~~~ bash
az network watcher connection-monitor list -l $location -o table
~~~

List the created connection-monitor tests.

Define new variables to query the connection-monitor results.

> TODO: How to assign my own LAW instead of the default.

~~~ bash
# lawid=$(az monitor log-analytics workspace list -g DefaultResourceGroup-SCUS --query [].customerId -o tsv)
lawid=$(az monitor log-analytics workspace list -g defaultresourcegroup-eus --query [].customerId -o tsv)
query="NWConnectionMonitorTestResult | where TimeGenerated > ago(5m) | sort by TestResult | project TestGroupName, TestResult | summarize count() by TestResult,TestGroupName"
~~~

Let´s have a look at our connection manager test results.

~~~ text
az monitor log-analytics query -w $lawid --analytics-query "$query" -o table

TableName      TestGroupName    TestResult    Count_
-------------  ---------------  ------------  --------
PrimaryResult  optospoketgrp    Pass          2
PrimaryResult  optohubtgrp      Pass          3
~~~

### Get tcp logs from hubVM:

~~~ bash
vmhubid=$(az vm show -g $prefix -n ${prefix}hubvm --query id -o tsv) # linked to pdns
az network bastion ssh -n ${prefix}hub -g $prefix --target-resource-id $vmhubid --auth-type password --username chpinoto
demo!pass123
sudo -i
tcpdump -i eth0 icmp
tcpdump -nnvvXSs 1514 -i eth0 icmp # with hex
logout # as root
logout
~~~

Result:

~~~ text
tcpdump: verbose output suppressed, use -v or -vv for full protocol decode
listening on eth0, link-type EN10MB (Ethernet), capture size 262144 bytes
06:51:00.442697 IP 172.16.0.5 > azcptdmonhubvm.internal.cloudapp.net: ICMP echo request, id 1046, seq 10097, length 12
06:51:00.442766 IP azcptdmonhubvm.internal.cloudapp.net > 172.16.0.5: ICMP echo reply, id 1046, seq 10097, length 12
06:51:10.441945 IP 172.16.0.5 > azcptdmonhubvm.internal.cloudapp.net: ICMP echo request, id 1046, seq 10099, length 12
06:51:10.442015 IP azcptdmonhubvm.internal.cloudapp.net > 172.16.0.5: ICMP echo reply, id 1046, seq 10099, length 12
06:51:20.441073 IP 172.16.0.5 > azcptdmonhubvm.internal.cloudapp.net: ICMP echo request, id 1046, seq 10101, length 12
~~~

### Azure VGW VPN connection tcp dump (connected):

~~~ bash
vpnconid=$(az network vpn-connection show -g $prefix -n ${prefix}hub --query id -o tsv)
az network vpn-connection packet-capture start -n ${prefix}hub -g $prefix
# get sas-url
saep=$(az storage account show -n $prefix --query primaryEndpoints.blob -o tsv) # get <my>.blob.core.windows.net
sasexpire=`date -u -d "5 minutes" '+%Y-%m-%dT%H:%MZ'`
sastoken=$(az storage container generate-sas --account-name $prefix -n $prefix --permissions acdlrw --expiry $sasexpire --auth-mode login --as-user -o tsv)
sasurl=${saep}${prefix}?${sastoken}
# retrieve data
az network vpn-connection packet-capture stop -n ${prefix}hub -g $prefix --sas-url $sasurl
~~~

To get the logs see Section "Azure VGW VPN connection tcp dump (disconnected)"

Capture only if the connection does get established:

~~~ bash
vpnconid=$(az network vpn-connection show -g $prefix -n ${prefix}hub --query id -o tsv)
az network vpn-connection packet-capture start -n ${prefix}hub -g $prefix
# az network vpn-connection packet-capture wait -n ${prefix}hub -g $prefix --custom provisioningState!=InProgress
~~~

Break VPN Connection
- based on https://www.shellhacks.com/cisco-no-shutdown-command-enable-disable-interface/

~~~ bash
vmopgwid=$(az vm show -g $prefix -n ${prefix}opgw --query id -o tsv)
az network bastion ssh -n ${prefix}op -g $prefix --target-resource-id $vmopgwid --auth-type password --username chpinoto
demo!pass123
# shut down tunnel
Conf t
interface Tunnel1
shutdown
end
write
Show int Tunnel1
# start tunnel
configure terminal
interface Tunnel1
no shutdown
end
write
Show int Tunnel1
ping 10.1.0.4 # TODO Success rate is 0 percent (0/5), should be 100%
logout
~~~

> NOTE: You can restart/reset azure vpn connection via the portal instead: https://docs.microsoft.com/en-us/azure/vpn-gateway/reset-gateway


Retrieve the logs
~~~ bash
 # get sas-url
saep=$(az storage account show -n $prefix --query primaryEndpoints.blob -o tsv) # get <my>.blob.core.windows.net
sasexpire=`date -u -d "5 minutes" '+%Y-%m-%dT%H:%MZ'`
sastoken=$(az storage container generate-sas --account-name $prefix -n $prefix --permissions acdlrw --expiry $sasexpire --auth-mode login --as-user -o tsv)
sasurl=${saep}${prefix}?${sastoken}
# retrieve data
az network vpn-connection packet-capture stop -n ${prefix}hub -g $prefix --sas-url $sasurl
~~~

### Network Security Groups [NSG].

We are going to make use of Network Security Groups [NSG]. Please not that request send from vm with internal IP via a VPN gateway public IP will be translated (NAT) before become visible to NSG. Therefore we do not need to add the public IP of our Gateways to the NSG. Instead we can just add the private IP of the clients.

> If you specify an address for an Azure resource, specify the private IP address assigned to the resource. Network security groups are processed after Azure translates a public IP address to a private IP address for inbound traffic, and before Azure translates a private IP address to a public IP address for outbound traffic. 
> Source: https://docs.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview

Connection flow with nsg and nat:

~~~ mermaid
sequenceDiagram
    critical OnPrem
    gwOP->nsgOP: connect to gwHUB pubIP
    Note right of nsgOP: validate 172.16.0.4 outbound
    nsgOP->natOP: sNAT 172.16.0.4 -> gwOP-pubIP
    end
    natOP->natHub: 
    critical Azure
    Note right of natHub: dNAT gwHub-pubIP -> 10.1.0.4
    Note right of natHub: sNAT gwOP-pubIP -> 172.16.0.4
    natHub->nsgHub: validate income gwOP 172.16.0.4
    nsgHub->gwHub: fwd connect
    end 
~~~

We just need NSG rules to SSH from our local machine into the VMs:

~~~ bash
# Hub VNet:
az network nsg rule list -g $prefix --nsg-name ${prefix}hub --query '[].{"name":name,"direction":direction,"src":sourceAddressPrefix,"des":destinationAddressPrefix}' -o table
~~~

Result:
~~~ text
Name    Direction    Src            Des
------  -----------  -------------  ----------
ssh     Inbound      91.56.247.197  10.1.0.4
op2az   Inbound      172.16.0.0/16  10.0.0.0/8
~~~

~~~ bash
# Hub VNet:
az network nsg rule list -g $prefix --nsg-name ${prefix}op --query '[].{"name":name,"direction":direction,"src":sourceAddressPrefix,"des":destinationAddressPrefix,"src[]":sourceAddressPrefixes[],"des[]":destinationAddressPrefixes[]}' -o table
~~~

Result:
~~~ text
Name    Direction    Src            Des
------  -----------  -------------  ----------
ssh     Inbound      91.56.247.197  10.1.0.4
op2az   Inbound      172.16.0.0/16  10.0.0.0/8
~~~



### Clean up:

~~~ bash
az group delete -n $prefix -y
~~~

## Misc

### ssh

~~~ bash
#ssh-keygen -R $vmopip
ssh -i azbicep/ssh/chpinoto.key chpinoto@$vmop1ip
demo!pass123
~~~

### Cisco

~~~ bash
Show run
Show crypto ikev2 sa
Show crypto ipsec sa
Show int Tunnel1
Show ip bgp summary
~~~

### nsg flow logs
- https://github.com/erjosito/get_nsg_logs
- https://docs.microsoft.com/en-us/azure/network-watcher/network-watcher-visualize-nsg-flow-logs-power-bi

### azure network manager

~~~ bash
az network manager post-commit --debug -n $prefix --commit-type "Connectivity" --target-locations $location -g $prefix --configuration-ids $nwmconid
# List all devices of spoke vnet/subnet:
az network vnet subnet show -g $prefix --vnet-name ${prefix}spoke1 -n $prefix --query ipConfigurations[].id -o tsv # expect 3 entries
~~~

### azure private links

~~~ bash
az network private-dns zone list -g $prefix --query [].name # list all private dns zones
plz="privatelink.blob.core.windows.net."
~~~

### windows server

- (Azure Site-To-Site (S2S) VPN With Windows Server 2019
)[https://blog.naglis.no/?p=3712]

~~~ powershell
Install-WindowsFeature -Name RemoteAccess, DirectAccess-VPN, Routing -IncludeManagementTools -Verbose
# verify
rrasmgmt.msc 
~~~

### git

- [submodules](https://git-scm.com/book/en/v2/Git-Tools-Submodules)

~~~ bash
prefix=azcptdmon
gh repo create $prefix --public
git init
git remote add origin https://github.com/cpinotossi/$prefix.git
git submodule add https://github.com/cpinotossi/azbicep
git submodule init
git submodule update
git submodule update --init
git status
git add *
git add .gitignore
git diff --cached --submodule
git commit -m"Need to re-run this once more before the final version"
git push origin main 
git push --recurse-submodules=on-demand
git rm README.md # unstage
git --help
git config advice.addIgnoredFile false
~~~

