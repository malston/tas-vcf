#!/bin/bash
export GOVC_URL="vc01.vcf.lab"
export GOVC_USERNAME="administrator@vsphere.local"
export GOVC_INSECURE="true"
export GOVC_DATACENTER="VCF-Datacenter"
export GOVC_PASSWORD=$(op read "op://Private/vc01.vcf.lab/password")

echo "=== Check VMware Tools Status ==="
govc vm.info ops-manager | grep -i "tools"

echo ""
echo "=== Try to list processes via VMware Tools ==="
govc guest.ps -vm ops-manager -json 2>&1 | head -20
