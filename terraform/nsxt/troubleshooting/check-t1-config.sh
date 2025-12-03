#!/bin/bash
NSX_PASSWORD=$(op read "op://Private/nsx01.vcf.lab/j_password")
T1_ID="3b62aea5-8dab-4eda-9ff3-62cd0249b4f6"

echo "=== T1 Router Configuration ==="
curl -sk -u "admin:${NSX_PASSWORD}" "https://nsx01.vcf.lab/policy/api/v1/infra/tier-1s/${T1_ID}" | jq '{display_name, tier0_path, route_advertisement_types}'

echo ""
echo "=== T1 Route Advertisement Rules ==="
curl -sk -u "admin:${NSX_PASSWORD}" "https://nsx01.vcf.lab/policy/api/v1/infra/tier-1s/${T1_ID}/locale-services" | jq '.results[0].route_advertisement_rules // "none"'
