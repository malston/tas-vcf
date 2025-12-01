#!/usr/bin/env bash
# scripts/setup-dns.sh
# Add TAS DNS entries to Pi-hole/Unbound

set -euo pipefail

DNS_SERVER="${DNS_SERVER:-192.168.10.2}"
DNS_USER="${DNS_USER:-root}"

# DNS entries to add
declare -A DNS_ENTRIES=(
    ["opsman.tas.vcf.lab"]="31.31.10.10"
    ["*.sys.tas.vcf.lab"]="31.31.10.20"
    ["*.apps.tas.vcf.lab"]="31.31.10.20"
    ["ssh.sys.tas.vcf.lab"]="31.31.10.21"
    ["tcp.tas.vcf.lab"]="31.31.10.22"
)

echo "DNS entries to configure:"
for hostname in "${!DNS_ENTRIES[@]}"; do
    ip="${DNS_ENTRIES[$hostname]}"
    echo "  $hostname -> $ip"
done

echo ""
echo "To add these entries to Pi-hole/Unbound on $DNS_SERVER:"
echo ""
echo "1. SSH to DNS server:"
echo "   ssh $DNS_USER@$DNS_SERVER"
echo ""
echo "2. Add entries to /etc/unbound/unbound.conf.d/tas.conf:"
echo ""
cat << 'EOF'
server:
    # TAS Ops Manager
    local-data: "opsman.tas.vcf.lab. A 31.31.10.10"
    local-data-ptr: "31.31.10.10 opsman.tas.vcf.lab"

    # TAS System Domain (wildcard)
    local-zone: "sys.tas.vcf.lab." redirect
    local-data: "sys.tas.vcf.lab. A 31.31.10.20"

    # TAS Apps Domain (wildcard)
    local-zone: "apps.tas.vcf.lab." redirect
    local-data: "apps.tas.vcf.lab. A 31.31.10.20"

    # TAS SSH
    local-data: "ssh.sys.tas.vcf.lab. A 31.31.10.21"

    # TAS TCP Router
    local-data: "tcp.tas.vcf.lab. A 31.31.10.22"
EOF
echo ""
echo "3. Restart Unbound:"
echo "   systemctl restart unbound"
echo ""
echo "4. Test resolution:"
echo "   dig @$DNS_SERVER opsman.tas.vcf.lab"
echo "   dig @$DNS_SERVER test.sys.tas.vcf.lab"
echo "   dig @$DNS_SERVER myapp.apps.tas.vcf.lab"
