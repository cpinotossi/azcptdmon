# Azure Private Link Demos

## Setup Private Link with Storage Account

~~~ mermaid
classDiagram
pe1 --> plDNS
pe1 --> storage1 : private link
pe1 --> spoke1 : inject
pe1: cptdpl1.blob.core.windows.net
pe2 --> storage2 : private link
pe2 --> spoke1 : inject 
pe2: cptdpl2.blob.core.windows.net
plDNS --> hub : link/resolve
plDNS --> spoke1 : link/resolve
plDNS: privatelink.blob.core.windows.net
hub --> spoke1 : peering
hub --> onprem : peering
hub : bastion
hub : cidr 10.1.0.0/16
hub : vm 10.1.0.4
onprem : cidr 172.16.0.0/16
onprem : vm 172.16.0.4
spoke1 : cidr 10.2.0.0/16
spoke1 : vm 10.2.0.4
spoke1 : pe1 10.2.0.5
spoke1 : pe2 10.2.0.6
storage1 : cptdpl1.blob.core.windows.net
storage2 : cptdp12.blob.core.windows.net
~~~

Define variables:

~~~ bash
prefix=cptdpl
location=eastus
myip=$(curl ifconfig.io) # Just in case we like to whitelist our own ip.
myobjectid=$(az ad user list --query '[?displayName==`ga`].id' -o tsv) # just in case we like to assing some RBAC roles to ourself.
~~~

Create foundation:

~~~ bash
az group create -n $prefix -l $location
az deployment group create -n $prefix -g $prefix --mode incremental --template-file bicep/deploy.bicep -p prefix=$prefix myobjectid=$myobjectid location=$location myip=$myip
~~~

Create Hub-Spoke peering with Azure Network Manager:

~~~ bash
vnetnames=$(az network vnet list -g $prefix --query [].name | tr -d '\n' | tr -d ' ')
az deployment group create -n $prefix -g $prefix --template-file bicep/deploy.vnm.bicep -p prefix=$prefix location=$location hubname=${prefix}hub vnetnames=$vnetnames
nwmconid=$(az network manager connect-config show --configuration-name $prefix -n $prefix -g $prefix --query id -o tsv) 
# Commit needs to be done via REST API for now, the cli is not working yet.
nwmbody="{\"targetLocations\": [\"$location\"],\"configurationIds\": [\"$nwmconid\"],\"commitType\": \"Connectivity\"}"
subid=$(az account show --query id -o tsv)
az rest --method post -u https://management.azure.com/subscriptions/$subid/resourceGroups/$prefix/providers/Microsoft.Network/networkManagers/$prefix/commit --url-parameters api-version=2021-02-01-preview -b "$nwmbody"
~~~

List all devices of spoke vnet/subnet:

~~~ bash
az network vnet subnet show -g $prefix --vnet-name ${prefix}spoke1 -n $prefix --query ipConfigurations[].id -o tsv # expect 3 entries
~~~

List all vnet linked to the private dns zone:

~~~ bash
az network private-dns link vnet list -g $prefix -z $plz --query [].id # expect 2 links
~~~

List private link private dns entries:

~~~ bash
az network private-dns record-set list -g $prefix -z $plz --query '[?type==`Microsoft.Network/privateDnsZones/A`].{aRecords:aRecords[0].ipv4Address,fqdn:fqdn}' -o table # expect 1 a records
~~~

Result:

~~~ text
ARecords    Fqdn
----------  ------------------------------------------
10.2.0.5    cptdpl1.privatelink.blob.core.windows.net.
~~~


Test DNS resolution from inside spoke1 vnet:

~~~ bash
vmspokeid=$(az vm show -g $prefix -n ${prefix}spoke1  --query id -o tsv) # linked to pdns
az network bastion ssh -n ${prefix}hub -g $prefix --target-resource-id $vmspokeid --auth-type password --username chpinoto
demo!pass123
dig +noall +answer cptdpl1.blob.core.windows.net. # expect 10.2.0.6 or 10.2.0.5
dig +noall +answer cptdpl1.privatelink.blob.core.windows.net. # expect 10.2.0.6 or 10.2.0.5
logout
~~~

Test DNS resolution from inside hub vnet:

~~~ bash
vmhubid=$(az vm show -g $prefix -n ${prefix}hub  --query id -o tsv) # not linked to pdns
az network bastion ssh -n ${prefix}hub -g $prefix --target-resource-id $vmhubid --auth-type password --username chpinoto
demo!pass123
dig +noall +answer cptdpl1.privatelink.blob.core.windows.net. # expect 10.2.0.6 or 10.2.0.5
logout
~~~

### Privat link and public endpoint

Turning on private link on storage account does not restrict access via public endpoint.
Upload content via public endpoint:

~~~ bash
az storage blob upload --data 'hello world' -c $prefix -n $prefix --account-name ${prefix}1 --auth-mode login
az storage blob list --auth-mode login --account-name ${prefix}1 --container-name $prefix
~~~

### Private link and NX response

> Private networks already using the private DNS zone for a given type, can only connect to public resources if they don't have any private endpoint connections, otherwise a corresponding DNS configuration is required on the private DNS zone in order to complete the DNS resolution sequence.
> (source: https://docs.microsoft.com/en-us/azure/private-link/private-endpoint-dns)

To confirm this we are going to send a DNS query for the second storage account:

~~~ bash
vmspokeid=$(az vm show -g $prefix -n ${prefix}spoke1  --query id -o tsv) # linked to pdns
az network bastion ssh -n ${prefix}hub -g $prefix --target-resource-id $vmspokeid --auth-type password --username chpinoto
demo!pass123
dig cptdpl2.blob.core.windows.net. # expect NXDOMAIN response
logout
~~~

To overcome this have a look at the following solution::
- https://github.com/cthoenes/azure-coredns-forwarder-sample

CONCLUSION:
- Private link does provide access to Azure Storage Account services via a private IP but it does not restrict access via the public endpoint.
- Private link does result into DNS NXDOMAIN response under certain cases.

Clean up:

~~~ bash
az group delete -n $prefix -y
~~~

## Misc

### azure network manager

~~~ bash
az network manager post-commit --debug -n $prefix --commit-type "Connectivity" --target-locations $location -g $prefix --configuration-ids $nwmconid
~~~

### azure private links

~~~ bash
az network private-dns zone list -g $prefix --query [].name # list all private dns zones
plz="privatelink.blob.core.windows.net."
~~~
### git

~~~ bash
gh repo create $prefix --public
git init
git remote add origin https://github.com/cpinotossi/$prefix.git
git status
git add *
git commit -m"NXDOMAIN case"
git push origin main 
~~~