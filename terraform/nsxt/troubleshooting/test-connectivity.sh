#!/bin/bash
echo "=== Testing connectivity from workstation ==="
echo ""

echo "1. Ping T0 uplink gateway (172.30.70.1):"
ping -c 2 172.30.70.1

echo ""
echo "2. Ping Ops Manager external IP (31.31.10.10):"
ping -c 2 31.31.10.10

echo ""
echo "3. Test HTTPS to Ops Manager:"
timeout 5 curl -sk https://31.31.10.10 || echo "Connection failed/timeout"

echo ""
echo "4. Check DNS resolution:"
dig +short opsman.tas.vcf.lab

echo ""
echo "5. Check if Ops Manager VM is reachable on internal IP:"
ping -c 2 10.0.1.10
