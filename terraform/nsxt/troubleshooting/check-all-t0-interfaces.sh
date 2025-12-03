#!/bin/bash
NSX_PASSWORD=$(op read "op://Private/nsx01.vcf.lab/j_password")

echo "=== All T0 Locale Services ==="
curl -sk -u "admin:${NSX_PASSWORD}" "https://nsx01.vcf.lab/policy/api/v1/infra/tier-0s/transit-gw/locale-services" | jq '.results[] | {id, edge_cluster_path}'

echo ""
echo "=== Checking all locale service interfaces ==="
for locale_id in $(curl -sk -u "admin:${NSX_PASSWORD}" "https://nsx01.vcf.lab/policy/api/v1/infra/tier-0s/transit-gw/locale-services" | jq -r '.results[].id'); do
  echo "--- Locale service: $locale_id ---"
  curl -sk -u "admin:${NSX_PASSWORD}" "https://nsx01.vcf.lab/policy/api/v1/infra/tier-0s/transit-gw/locale-services/${locale_id}/interfaces" | jq '.results[] | {display_name, type, subnets, segment_path}'
done
