# NSX Manager Alarms

## MTU Check Alarm

Reported by Node: nsx01a (172.30.0.16)
First Reported: Nov 24, 2025, 4:00:06 PM

| Feature   | Event Type                         | Entity Name          | Entity Type         | Severity | Last Reported Time      | Alarm State |
| ----------|------------------------------------|----------------------|---------------------|----------|-------------------------|-------------|
| MTU Check | MTU Mismatch Within Transport Zone | nsx01a (172.30.0.16) | Cluster Node Config | High     | Dec 4, 2025, 5:46:23 AM | Open        |

### Description

MTU configuration mismatch between Transport Nodes (ESXi, KVM and Edge) attached to the same Transport Zone. MTU values on all switches attached to the same Transport Zone not being consistent will cause connectivity issues.

### Investigation Status

**Date**: December 4, 2025
**Status**: ✅ RESOLVED
**Resolution Time**: ~3 hours (including 30-minute account lockout wait and alarm auto-clear delay)
**Fix Applied**: Updated NSX Global MTU from 1700 → 9000 to match VDS jumbo frame configuration
**Final Configuration**: All MTU values set to 9000 (jumbo frames) across VDS and NSX

### Root Cause Analysis

Based on VCF 9 deployment patterns and VMware documentation (2025), this MTU mismatch likely stems from one of these scenarios:

1. **Default vs Recommended MTU**
   - VCF deployment used default MTU 1500
   - NSX overlay requires minimum 1600 (recommended 1700) for Geneve encapsulation
   - Result: Insufficient MTU causing fragmentation

2. **ESXi vs Edge Node Mismatch**
   - ESXi hosts: Default MTU 1500
   - Edge nodes: Different MTU configuration
   - Result: Inconsistent Transport Zone configuration

3. **Mixed Jumbo Frame Configuration**
   - Some nodes: Configured for jumbo frames (9000)
   - Other nodes: Left at default (1500)
   - Physical switches: May or may not support 9000

### VMware MTU Requirements (VCF 9)

- **Minimum**: 1600 bytes
- **Recommended**: 1700 bytes (future-proof for expanding Geneve header)
- **Optimal**: 9000 bytes (jumbo frames) if physical infrastructure supports
- **Guest VMs**: 8800 MTU if using 9000 on infrastructure (accounts for 100-200 byte Geneve overhead)

### Configuration Layers to Check

MTU must be consistent across these layers:

1. **Global Switching Config**: `physical_uplink_mtu` parameter
2. **Host Switch Profiles**: Uplink profile MTU settings
3. **vSphere VDS**: Distributed switch MTU configuration
4. **Physical Switches**: Underlying network infrastructure MTU

### Prepared Fix Procedure

**Scripts Created**:
- `/tmp/diagnose-and-fix-mtu.sh` - Comprehensive MTU diagnosis
- `/tmp/fix-mtu-mismatch.sh` - Apply consistent MTU configuration

**Steps After Account Unlock**:

1. **Diagnose Current State**:
   ```bash
   chmod +x /tmp/diagnose-and-fix-mtu.sh
   ./diagnose-and-fix-mtu.sh
   ```

2. **Review Findings**:
   - Identify which nodes have mismatched MTU values
   - Check physical infrastructure capabilities
   - Choose target MTU (1700 minimum or 9000 for jumbo frames)

3. **Apply Fix**:
   ```bash
   chmod +x /tmp/fix-mtu-mismatch.sh
   # For minimum recommended MTU:
   ./fix-mtu-mismatch.sh 1700
   # OR for jumbo frames (if infrastructure supports):
   ./fix-mtu-mismatch.sh 9000
   ```

4. **Verify**:
   - Wait 5 minutes for changes to propagate
   - Check NSX UI: System → Fabric → Settings → MTU Configuration Check
   - Verify alarm clears

### References

- [VCF 9 MTU Guidance (Broadcom)](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-9-0-and-later/9-0/advanced-network-management/administration-guide/transport-zones-and-transport-nodes/mtu-guidance.html)
- [MTU Mismatch Alarm KB](https://knowledge.broadcom.com/external/article/330488/mtu-mismatch-within-transport-zone-alarm.html)
- [NSX-T 4.x Overlay Networking MTU](https://digitalthoughtdisruption.com/2025/07/15/nsx-t-4x-overlay-networking-architecture-mtu-troubleshooting/)
- [Configure Jumbo Frame Support](https://blog.zuthof.nl/2025/01/20/configure-jumbo-frame-support-in-nsx/)

### Resolution Details

**Actual Root Cause:**
- **VDS MTU in vCenter**: 9000 (jumbo frames, configured by VCF)
- **NSX Global MTU**: 1700 (minimum recommended, default)
- **Result**: Mismatch detected - VDS using jumbo frames, NSX expecting standard MTU

**What Was Fixed:**
1. **Global Physical Uplink MTU**: Updated from 1700 → 9000
2. **Remote Tunnel Physical MTU**: Updated from 1700 → 9000
3. **Result**: NSX configuration now matches VDS jumbo frame configuration

**Why the Fix Worked:**
The host switch profile `vc01-VCF-Mgmt-Cluster-sddc1-cl01-vds01` is VDS-backed (vSphere Distributed Switch). NSX correctly enforces that VDS MTU must be configured in vCenter, not NSX:

> "The MTU for VDS switches should not be specified in NSX. Please update the MTU in vCenter"

Since VCF had already configured the VDS with jumbo frames (9000 MTU), the solution was to update NSX global configuration to match. After updating both MTU parameters to 9000:
1. MTU Configuration Check showed "Consistent"
2. Alarm auto-cleared within 5 minutes on next polling cycle
3. All transport nodes now properly configured for jumbo frames

**Commands Executed:**
```bash
# Initial diagnosis (found global MTU 1700, VDS MTU unknown)
bash /tmp/diagnose-and-fix-mtu.sh

# First attempt: Set NSX to 1700 (didn't resolve alarm)
bash /tmp/fix-mtu-mismatch.sh 1700

# Checked VDS MTU in vCenter: Found it was 9000
# Manual check via vCenter UI revealed VDS MTU = 9000

# Second attempt: Set NSX to 9000 to match VDS
bash /tmp/fix-mtu-mismatch.sh 9000

# Updated remote tunnel MTU to match
bash /tmp/fix-remote-tunnel-mtu.sh

# Verified configuration consistent
# System → Fabric → Settings → MTU Configuration Check: "Consistent"

# Alarm auto-cleared after ~5 minutes
```

**Key Discovery:**
Checking the VDS MTU in vCenter (not visible via NSX API) was the critical step that identified the true root cause.

### Lessons Learned

1. **Account Lockout Prevention**: NSX locks accounts after ~5 failed authentication attempts. Always verify credentials (use `op read` for 1Password) before API troubleshooting.

2. **VCF 9 VDS Management**: In VCF deployments, host switch profiles linked to vSphere Distributed Switches must have MTU configured in vCenter, not NSX. NSX enforces this separation of concerns.

3. **Global MTU as Source of Truth**: Updating the global MTU configuration can trigger NSX to re-validate transport nodes and clear stale alarms, even when individual profiles can't be updated directly.

4. **MTU Planning**: MTU configuration should be determined during initial deployment. The recommended 1700 bytes provides headroom for Geneve encapsulation (100-200 bytes overhead).

5. **VCF Abstractions**: Traditional NSX-T APIs may return empty results or "not configured" for VCF-managed resources. This is expected behavior when VCF manages the underlying infrastructure.
