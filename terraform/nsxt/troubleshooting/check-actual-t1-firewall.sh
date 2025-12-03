#!/bin/bash
NSX_PASSWORD=$(op read "op://Private/nsx01.vcf.lab/j_password")
T1_ID="3b62aea5-8dab-4eda-9ff3-62cd0249b4f6"

echo "=== T1 Gateway Firewall Configuration ==="
curl -sk -u "admin:${NSX_PASSWORD}" "https://nsx01.vcf.lab/policy/api/v1/infra/tier-1s/${T1_ID}" | jq '{display_name, enable_firewall, default_rule_logging, tier0_path}'

echo ""
echo "=== Check for Gateway Firewall Rules on this T1 ==="
curl -sk -u "admin:${NSX_PASSWORD}" "https://nsx01.vcf.lab/policy/api/v1/infra/domains/default/gateway-policies" | jq '.results[] | select(.category == "LocalGatewayRules") | {display_name, rules: .rules[]?}'
