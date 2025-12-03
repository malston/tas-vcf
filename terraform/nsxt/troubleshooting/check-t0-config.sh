#!/bin/bash
NSX_PASSWORD=$(op read "op://Private/nsx01.vcf.lab/j_password")

echo "=== T0 Gateway Configuration ==="
curl -sk -u "admin:${NSX_PASSWORD}" "https://nsx01.vcf.lab/policy/api/v1/infra/tier-0s/transit-gw" | jq '{display_name, ha_mode}'

echo ""
echo "=== T0 Locale Services (uplinks) ==="
curl -sk -u "admin:${NSX_PASSWORD}" "https://nsx01.vcf.lab/policy/api/v1/infra/tier-0s/transit-gw/locale-services" | jq '.results[] | {id, edge_cluster_path}'

echo ""
echo "=== T0 External Interfaces ==="
curl -sk -u "admin:${NSX_PASSWORD}" "https://nsx01.vcf.lab/policy/api/v1/infra/tier-0s/transit-gw/locale-services/default/interfaces" | jq '.results[] | {display_name, type, subnets}'
