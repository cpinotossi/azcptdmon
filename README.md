# Azure Monitor Demos

## Connection Monitor (WORK IN PROGRESS)

~~~ mermaid
classDiagram
hub --> spoke1 : peering
hub --> onprem : vpn
hub : cidr 10.1.0.0/16
hub : bastion
hub : vgw pubip
hub : vm 10.1.0.4
onprem : cidr 172.16.0.0/16
spoke1 : cidr 10.2.0.0/16
vmhub --> hub
vmhub: 10.1.0.4
vmspoke1 --> spoke1
vmspoke1: 10.2.0.4
vmop --> onprem
vmop: 172.16.0.4
~~~

Define variables:

~~~ bash
prefix=azcptdmon
location=eastus
myip=$(curl ifconfig.io) # Just in case we like to whitelist our own ip.
myobjectid=$(az ad user list --query '[?displayName==`ga`].id' -o tsv) # just in case we like to assing some RBAC roles to ourself.
~~~

Create foundation:

~~~ bash
az group create -n $prefix -l $location
az deployment group create -n $prefix -g $prefix --mode incremental --template-file deploy.bicep -p prefix=$prefix myobjectid=$myobjectid location=$location myip=$myip
~~~

Create Hub-Spoke peering with Azure Network Manager:

~~~ bash
vnetnames=$(az network vnet list -g $prefix --query [].name | tr -d '\n' | tr -d ' ')
az deployment group create -n $prefix -g $prefix --template-file azbicep/bicep/deploy.vnm.bicep -p prefix=$prefix location=$location hubname=${prefix}hub vnetnames=$vnetnames
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

Test connectivity spoke1 vm to onprem vm:

~~~ bash
vmspokeid=$(az vm show -g $prefix -n ${prefix}spoke1  --query id -o tsv) # linked to pdns
az network bastion ssh -n ${prefix}hub -g $prefix --target-resource-id $vmspokeid --auth-type password --username chpinoto
demo!pass123
dig +noall +answer cptdpl1.blob.core.windows.net. # expect 10.2.0.6 or 10.2.0.5
dig +noall +answer cptdpl1.privatelink.blob.core.windows.net. # expect 10.2.0.6 or 10.2.0.5
logout
~~~

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
git commit -m"init"
git push origin main 
git rm README.md # unstage
git --help
~~~