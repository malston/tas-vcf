#!/bin/bash
NSX_PASSWORD=$(op read "op://Private/nsx01.vcf.lab/j_password")

echo "=== T1 Infrastructure Gateway Firewall Rules ==="
curl -sk -u "admin:${NSX_PASSWORD}" "https://nsx01.vcf.lab/policy/api/v1/infra/domains/default/gateway-policies" | jq '.results[] | select(.display_name | contains("tas")) | {display_name, id}'

echo ""
echo "=== Check for DNAT rule details ==="
curl -sk -u "admin:${NSX_PASSWORD}" "https://nsx01.vcf.lab/policy/api/v1/infra/tier-0s/transit-gw/nat/USER/nat-rules/tas-DNAT-OpsManager" | jq '{display_name, action, destination_networks, translated_networks, enabled, firewall_match}'
