# Ops Manager TCP Connectivity Issue

## Problem Summary

Ops Manager VM deploys successfully but TCP services (SSH port 22, HTTPS port 443) do not respond, while ICMP ping works correctly. This is a recurring issue that persists across multiple deployment attempts.

## Symptoms

- ✅ **ICMP (ping) works**: Can ping 31.31.10.10 successfully (~190ms latency)
- ✅ **Large ICMP packets work**: 1400-byte packets succeed (rules out MTU issues)
- ✅ **VM boots successfully**: Console shows login prompt
- ✅ **IP configuration correct**: VM has 10.0.1.10, VMware Tools reports IP
- ✅ **NAT functional**: DNAT rule 31.31.10.10 → 10.0.1.10 exists and works for ICMP
- ❌ **SSH (port 22) times out**: Connection attempts timeout
- ❌ **HTTPS (port 443) times out**: Connection attempts timeout

## Network Configuration

### NSX-T Infrastructure
- **T0 Gateway**: transit-gw
- **T1 Gateway**: tas-T1-Infrastructure (ID: 3b62aea5-8dab-4eda-9ff3-62cd0249b4f6)
- **T1 Firewall**: DISABLED (enable_firewall = false)
- **Segment**: tas-Infrastructure (10.0.1.0/24, gateway 10.0.1.1)

### NAT Rules (on T0 transit-gw)
```
tas-SNAT-All:        SNAT 10.0.0.0/16      → 31.31.10.1
tas-SNAT-OpsManager: SNAT 10.0.1.10        → 31.31.10.10
tas-DNAT-OpsManager: DNAT 31.31.10.10      → 10.0.1.10
```

### VM Configuration
- **Name**: ops-manager
- **Internal IP**: 10.0.1.10/24
- **Gateway**: 10.0.1.1
- **DNS**: 192.168.10.2
- **External IP**: 31.31.10.10 (via DNAT)
- **Hostname**: opsman.tas.vcf.lab
- **Resource Pool**: tas-infrastructure
- **Network**: tas-Infrastructure segment

## Deployment Details

### OVA Properties Configured
```json
{
  "ip0": "10.0.1.10",
  "netmask0": "255.255.255.0",
  "gateway": "10.0.1.1",
  "DNS": "192.168.10.2",
  "ntp_servers": "pool.ntp.org",
  "public_ssh_key": "<SSH public key>",
  "custom_hostname": "opsman.tas.vcf.lab"
}
```

### Authentication
- **SSH Key**: Configured via vApp property `public_ssh_key`
- **Console Password**: NOT SET (deployment script attempted to set via SSH but SSH was unavailable)
- **Expected Username**: ubuntu

## Root Cause Analysis

### What We've Ruled Out

1. **T0 Gateway Connectivity**: ICMP works, proving T0 routing functional
2. **NAT Configuration**: ICMP proves DNAT/SNAT rules work
3. **T1 Gateway Firewall**: Disabled (enable_firewall = false)
4. **MTU Issues**: Large ICMP packets (1400 bytes) succeed
5. **VM Boot Issues**: Console shows login prompt, VM healthy
6. **Network Segmentation**: VM on correct segment with proper gateway

### Most Likely Causes

1. **VM Internal Firewall (ufw/iptables)**
   - Ops Manager OVA may have restrictive firewall rules by default
   - Firewall could be blocking TCP while allowing ICMP
   - Would explain consistent behavior across deployments

2. **Services Not Started**
   - SSH daemon may not be running
   - HTTPS service may not be running
   - Less likely given 20+ minutes since boot

3. **Service Binding Issue**
   - Services might be bound to wrong interface
   - Could be listening on localhost only

## Diagnostic Steps Needed

### Via Console Access (Requires Password)

1. **Check SSH Service Status**
   ```bash
   sudo systemctl status ssh
   sudo systemctl status sshd
   ```

2. **Check Listening Ports**
   ```bash
   sudo ss -tlnp | grep -E ':(22|443)'
   sudo netstat -tlnp | grep -E ':(22|443)'
   ```

3. **Check Firewall Rules**
   ```bash
   sudo ufw status verbose
   sudo iptables -L -n -v
   ```

4. **Check Network Configuration**
   ```bash
   ip addr show
   ip route show
   ping -c 3 10.0.1.1
   ping -c 3 192.168.10.2
   ```

5. **Check System Logs**
   ```bash
   sudo journalctl -u ssh -n 50
   sudo dmesg | tail -50
   ```

## Solutions

### Solution 1: Access Console via GRUB Single-User Mode

Since we don't have a password set, boot into single-user mode to set one:

1. **Access vSphere Console**
   - Navigate to vc01.vcf.lab vSphere Client
   - Find ops-manager VM
   - Right-click → Launch Web Console

2. **Reboot into Single-User Mode**
   - Reboot VM: Ctrl+Alt+Del in console
   - Press `e` when GRUB menu appears
   - Find line starting with `linux`
   - Add `single` or `init=/bin/bash` at end of line
   - Press Ctrl+X or F10 to boot

3. **Set Password**
   ```bash
   # Remount root as read-write
   mount -o remount,rw /

   # Set password for ubuntu user
   passwd ubuntu
   # Enter: VMware1!

   # Sync and reboot
   sync
   reboot -f
   ```

4. **Login and Investigate**
   - Login as ubuntu with password VMware1!
   - Run diagnostic commands above
   - Check firewall: `sudo ufw status`
   - If firewall blocking: `sudo ufw allow 22/tcp && sudo ufw allow 443/tcp`

### Solution 2: Redeploy with Known Configuration

If console access doesn't work, redeploy using a simpler approach:

1. **Test with Standard vSphere Network First**
   - Deploy to standard port group (non-NSX) temporarily
   - Verify OVA works with basic networking
   - Isolates NSX-T overlay vs OVA issue

2. **Test with DHCP Instead of Static IP**
   - Deploy without static IP configuration
   - Check if vApp properties cause issues

3. **Use Different Ops Manager Version**
   - Try newer/older OVA version
   - Check compatibility matrix

## Files Reference

- **Deployment Script**: `/Users/markalston/workspace/tas-vcf/scripts/deploy-opsman-v2.sh`
- **Terraform Config**: `/Users/markalston/workspace/tas-vcf/terraform/nsxt/`
- **Console Screenshot**: `/tmp/opsman-console.png`
- **Import Spec**: `/tmp/opsman-import-final-v2.json`

## NSX-T Verification Commands

```bash
# Export credentials
export NSX_MANAGER="nsx01.vcf.lab"
export NSX_USERNAME="admin"
export NSX_PASSWORD=$(op read "op://Private/nsx01.vcf.lab/password")

# Check T1 gateway firewall status
curl -k -u "$NSX_USERNAME:$NSX_PASSWORD" -X GET \
  "https://$NSX_MANAGER/policy/api/v1/infra/tier-1s/tas-T1-Infrastructure" \
  | jq '.enable_firewall'

# Check NAT rules
curl -k -u "$NSX_USERNAME:$NSX_PASSWORD" -X GET \
  "https://$NSX_MANAGER/policy/api/v1/infra/tier-0s/transit-gw/nat/USER/nat-rules" \
  | jq '.results[] | select(.display_name | contains("tas"))'
```

## Next Steps

1. **Immediate**: Access console via GRUB single-user mode and set password
2. **Investigate**: Check firewall rules and service status
3. **Fix**: Adjust firewall or restart services as needed
4. **Document**: Update this file with findings and solution

## Timeline

- **2025-12-03 20:48**: VM deployed and booted
- **2025-12-03 21:00**: Confirmed ICMP works, TCP fails
- **2025-12-03 21:15**: Ruled out T1 firewall, NAT, and MTU issues
- **2025-12-03 21:20**: Identified need for console access

## Lessons Learned

1. **T1 Firewalls**: When enabled without rules, they block all TCP by default (ICMP allowed for troubleshooting)
2. **T0 NAT Display**: NSX-T UI shows "Not Set" for External IP when using T0-level NAT (expected behavior)
3. **OVA Authentication**: Ops Manager OVA supports SSH keys but setting console password requires SSH access (chicken-and-egg)
4. **Deployment Validation**: Need better post-deployment validation that catches TCP connectivity issues early
