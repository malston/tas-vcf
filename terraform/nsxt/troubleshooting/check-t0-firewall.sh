#!/bin/bash
NSX_PASSWORD=$(op read "op://Private/nsx01.vcf.lab/j_password")

echo "=== T0 Gateway Firewall Status ==="
curl -sk -u "admin:${NSX_PASSWORD}" "https://nsx01.vcf.lab/policy/api/v1/infra/tier-0s/transit-gw" | jq '{display_name, ha_mode, firewall_enabled: .enable_firewall}'

echo ""
echo "=== Testing ping again (should still work) ==="
ping -c 2 31.31.10.10

echo ""
echo "=== Try telnet to port 22 ==="
timeout 5 telnet 31.31.10.10 22 2>&1 | head -5
