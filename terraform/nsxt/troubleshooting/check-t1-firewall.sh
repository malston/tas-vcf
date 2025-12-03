#!/bin/bash
NSX_PASSWORD=$(op read "op://Private/nsx01.vcf.lab/j_password")

echo "=== T1 Infrastructure Gateway Firewall Status ==="
curl -sk -u "admin:${NSX_PASSWORD}" "https://nsx01.vcf.lab/policy/api/v1/infra/tier-1s/tas-T1-Infrastructure" | jq '{display_name, enable_firewall, failover_mode}'

echo ""
echo "=== Check Gateway Firewall Policies ==="
curl -sk -u "admin:${NSX_PASSWORD}" "https://nsx01.vcf.lab/policy/api/v1/infra/domains/default/gateway-policies" | jq '.results[] | select(.display_name | contains("tas") or contains("T1-Infrastructure") or contains("default")) | {display_name, id, category}'

echo ""
echo "=== Check Default Gateway Firewall Policy ==="
curl -sk -u "admin:${NSX_PASSWORD}" "https://nsx01.vcf.lab/policy/api/v1/infra/domains/default/gateway-policies/default-layer3-section" 2>&1 | jq '.rules[]? | {display_name, action, services, scope}' 2>&1 || echo "No default policy or error"

echo ""
echo "=== Verify NAT rule allows all protocols ==="
curl -sk -u "admin:${NSX_PASSWORD}" "https://nsx01.vcf.lab/policy/api/v1/infra/tier-0s/transit-gw/nat/USER/nat-rules" | jq '.results[] | select(.display_name | contains("tas")) | {display_name, action, destination_networks, translated_networks, service, enabled}'
