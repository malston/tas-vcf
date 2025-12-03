#!/bin/bash
NSX_PASSWORD=$(op read "op://Private/nsx01.vcf.lab/j_password")

echo "=== Check All Gateway Firewall Policies ==="
curl -sk -u "admin:${NSX_PASSWORD}" "https://nsx01.vcf.lab/policy/api/v1/infra/domains/default/gateway-policies" | jq '.results[] | {display_name, category, rules: (.rules[]? | {display_name, action, source_groups, destination_groups, services, scope})}' 2>&1

echo ""
echo "=== Check Default Edge Firewall Policy ==="
curl -sk -u "admin:${NSX_PASSWORD}" "https://nsx01.vcf.lab/policy/api/v1/infra/domains/default/gateway-policies/default-layer3-section" | jq '.' 2>&1

echo ""
echo "=== Check T0 Gateway Security Features ==="
curl -sk -u "admin:${NSX_PASSWORD}" "https://nsx01.vcf.lab/policy/api/v1/infra/tier-0s/transit-gw" | jq '{display_name, enable_firewall, default_rule_logging}'
