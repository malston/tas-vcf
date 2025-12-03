#!/bin/bash
NSX_PASSWORD=$(op read "op://Private/nsx01.vcf.lab/j_password")
echo "=== All Segments ==="
curl -sk -u "admin:${NSX_PASSWORD}" "https://nsx01.vcf.lab/policy/api/v1/infra/segments" | jq -r '.results[] | "\(.display_name) - T1: \(.connectivity_path // "none") - Gateway: \(.subnets[0].gateway_address // "none")"'
