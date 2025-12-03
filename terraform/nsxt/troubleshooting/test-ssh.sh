#!/bin/bash
echo "=== Verify SSH key exists and has correct permissions ==="
ls -la ~/.ssh/vcf_opsman_ssh_key

echo ""
echo "=== Try SSH with verbose output ==="
timeout 10 ssh -vv -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i ~/.ssh/vcf_opsman_ssh_key ubuntu@31.31.10.10 "echo 'SUCCESS!'" 2>&1
