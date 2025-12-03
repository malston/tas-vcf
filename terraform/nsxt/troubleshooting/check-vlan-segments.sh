#!/bin/bash
NSX_PASSWORD=$(op read "op://Private/nsx01.vcf.lab/j_password")

echo "=== Checking for VLAN segments ==="
curl -sk -u "admin:${NSX_PASSWORD}" "https://nsx01.vcf.lab/policy/api/v1/infra/segments" | jq -r '.results[] | select(.vlan_ids != null) | {display_name, vlan_ids, connectivity_path}'

echo ""
echo "=== Checking T0 static routes ==="
curl -sk -u "admin:${NSX_PASSWORD}" "https://nsx01.vcf.lab/policy/api/v1/infra/tier-0s/transit-gw/static-routes" | jq '.'
