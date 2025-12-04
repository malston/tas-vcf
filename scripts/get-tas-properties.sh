#!/usr/bin/env bash
set -euo pipefail

opsman_password=$(op read "op://Private/opsman.tas.vcf.lab/password")

om --target opsman.tas.vcf.lab \
   --username admin \
   --password "$opsman_password" \
   --skip-ssl-validation \
   curl -p /api/v0/staged/products/cf-85da7fd88e99806e5d08/properties | \
   jq -r '.properties | keys | .[]'
