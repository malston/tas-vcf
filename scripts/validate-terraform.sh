#!/usr/bin/env bash
# scripts/validate-terraform.sh
# Validate Terraform configurations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Validating Terraform configurations..."
echo ""

for module in nsxt vsphere certs; do
    module_path="$PROJECT_ROOT/terraform/$module"
    if [[ -d "$module_path" ]]; then
        echo "=== Validating $module module ==="
        cd "$module_path"
        terraform init -backend=false
        terraform validate
        terraform fmt -check -diff
        echo "✓ $module module is valid"
        echo ""
    fi
done

echo "All Terraform modules validated successfully!"
