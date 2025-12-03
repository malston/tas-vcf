#!/bin/bash
export GOVC_URL="vc01.vcf.lab"
export GOVC_USERNAME="administrator@vsphere.local"
export GOVC_INSECURE="true"
export GOVC_DATACENTER="VCF-Datacenter"
export GOVC_PASSWORD=$(op read "op://Private/vc01.vcf.lab/password")

echo "=== Ops Manager VM Status ==="
govc vm.info ops-manager

echo ""
echo "=== VM Power State and IP ==="
govc vm.info -json ops-manager | jq '{name, powerState, ip, toolsStatus}' -c | jq .VirtualMachines[0] | jq '{name: .Name, powerState: .Runtime.PowerState, ip: .Guest.IpAddress, toolsStatus: .Guest.ToolsStatus}'
