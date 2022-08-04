targetScope='resourceGroup'

//var parameters = json(loadTextContent('parameters.json'))
param location string
var username = 'chpinoto'
var password = 'demo!pass123'
param prefix string
param myobjectid string
param myip string

module law 'azbicep/bicep/law.bicep' = {
  name: 'lawdeploy'
  params: {
    location: location
    prefix: prefix
  }
}

module sab 'azbicep/bicep/sab.bicep' = {
  name: 'sabdeploy'
  params: {
    location: location
    myObjectId: myobjectid
    postfix: ''
    prefix: prefix
  }
}

module opvnetmodule 'azbicep/bicep/vnetop.bicep' = {
  name: 'opvnetdeploy'
  params: {
    prefix: prefix
    postfix: 'op'
    location: location
    cidervnet: '172.16.0.0/16'
    cidersubnet: '172.16.0.0/24'
    ciderbastion: '172.16.1.0/24'
    desip:'172.16.0.4' // cisco vpn gateway
    descider: '10.0.0.0/8'
    srcip: myip
    gwip: '172.16.0.4' // cisco vpn gateway
  }
}

module opgwmodule 'azbicep/bicep/vm.bicep' = {
  name: 'opgwdeploy'
  params: {
    prefix: prefix
    postfix: 'opgw'
    vnetname: opvnetmodule.outputs.vnetname
    location: location
    username: username
    password: password
    myObjectId: myobjectid
    privateip: '172.16.0.4'
    imageRef: 'cisco'
    haspubip: true
    isipff: true
  }
  dependsOn:[
    opvnetmodule
  ]
}

module hubvnetmodule 'azbicep/bicep/vnethub.bicep' = {
  name: 'hubvnetdeploy'
  params: {
    prefix: prefix
    postfix: 'hub'
    location: location
    cidervnet: '10.1.0.0/16'
    cidersubnet: '10.1.0.0/24'
    ciderbastion: '10.1.1.0/24'
    ciderdnsrin: '10.1.2.0/24'
    ciderdnsrout: '10.1.3.0/24'
    cidergw: '10.1.4.0/24'
    opvpnip: opgwmodule.outputs.pubip
    cidrop: '172.16.0.0/16'
    desip:'10.1.0.4' // default vm in hub
    srcip: myip
  }
  dependsOn:[
    opgwmodule
  ]
}

module spokevnetmodule 'azbicep/bicep/vnetspoke.bicep' = {
  name: 'spokevnetdeploy'
  params: {
    prefix: prefix
    postfix: 'spoke'
    location: location
    cidervnet: '10.2.0.0/16'
    cidersubnet: '10.2.0.0/24'
  }
}

module opvmmodule 'azbicep/bicep/vm.bicep' = {
  name: 'opvmdeploy'
  params: {
    prefix: prefix
    postfix: 'opvm'
    vnetname: opvnetmodule.outputs.vnetname
    location: location
    username: username
    password: password
    myObjectId: myobjectid
    privateip: '172.16.0.5'
    imageRef: 'linux'
  }
  dependsOn:[
    opvnetmodule
  ]
}

module hubvmmodule 'azbicep/bicep/vm.bicep' = {
  name: 'hubvmdeploy'
  params: {
    prefix: prefix
    postfix: 'hubvm'
    vnetname: hubvnetmodule.outputs.vnetname
    location: location
    username: username
    password: password
    myObjectId: myobjectid
    privateip: '10.1.0.4'
    imageRef: 'linux'
  }
  dependsOn:[
    hubvnetmodule
  ]
}

module spokevmmodule 'azbicep/bicep/vm.bicep' = {
  name: 'spokevmdeploy'
  params: {
    prefix: prefix
    postfix: 'spokevm'
    vnetname: spokevnetmodule.outputs.vnetname
    location: location
    username: username
    password: password
    myObjectId: myobjectid
    privateip: '10.2.0.4'
    imageRef: 'linux'
  }
  dependsOn:[
    spokevnetmodule
  ]
}

module peering1module 'azbicep/bicep/vpeer.bicep' = {
  name: 'peering1deploy'
  params: {
    vnethubname: hubvnetmodule.outputs.vnetname
    vnetspokename: spokevnetmodule.outputs.vnetname
  }
  dependsOn:[
    vgwmodule
  ]
}

module vgwmodule 'azbicep/bicep/vgw.bicep' = {
  name: 'vgwmoduledeploy'
  params: {
    location: location
    postfix: 'hub'
    prefix: prefix
    vnetname: '${prefix}hub'
    localGatewayIpAddress: opgwmodule.outputs.pubip
    sharedKey: 'demo!pass123'
    vnetopname: opvnetmodule.outputs.vnetname
    bgpip: opgwmodule.outputs.pubip
  }
  dependsOn:[
    hubvnetmodule
    opgwmodule
  ]
}
