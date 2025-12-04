#!/usr/bin/env bash
set -euo pipefail

opsman_password=$(op read "op://Private/opsman.tas.vcf.lab/password")

om --target opsman.tas.vcf.lab \
   --username admin \
   --password "$opsman_password" \
   --skip-ssl-validation \
   pending-changes
