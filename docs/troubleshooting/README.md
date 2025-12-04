# Troubleshooting Scripts and Documentation

## MTU Configuration Scripts

### diagnose-mtu.sh
**Purpose**: Comprehensive MTU configuration diagnosis for NSX

**Usage**:
```bash
bash troubleshooting/diagnose-mtu.sh
```

**What it checks**:
- Global Switching Configuration (physical_uplink_mtu, remote_tunnel_physical_mtu)
- Host Switch Profiles and their MTU settings
- Transport Zones
- Transport Nodes (ESXi hosts and Edge nodes)
- Active MTU alarms

**When to use**:
- When investigating MTU mismatch alarms
- Before making MTU configuration changes
- To verify current MTU settings across NSX environment

---

### fix-mtu-mismatch.sh
**Purpose**: Apply consistent MTU configuration across NSX infrastructure

**Usage**:
```bash
bash troubleshooting/fix-mtu-mismatch.sh [1700|9000]
```

**Arguments**:
- `1700`: Minimum recommended MTU for NSX overlay (conservative, works everywhere)
- `9000`: Jumbo frames (optimal performance, requires physical infrastructure support)

**What it does**:
1. Updates global physical uplink MTU
2. Attempts to update host switch profiles (may fail for VDS-backed profiles)
3. Waits for changes to propagate
4. Verifies alarm status

**When to use**:
- After diagnosing MTU mismatch
- When you need to standardize MTU across all transport nodes
- **Important**: Check VDS MTU in vCenter first (must match the target MTU)

---

### fix-remote-tunnel-mtu.sh
**Purpose**: Update remote tunnel physical MTU to match physical uplink MTU

**Usage**:
```bash
bash troubleshooting/fix-remote-tunnel-mtu.sh
```

**What it does**:
- Updates `remote_tunnel_physical_mtu` to 9000
- Waits 30 seconds for NSX to re-evaluate
- Checks if MTU alarms cleared

**When to use**:
- When `physical_uplink_mtu` and `remote_tunnel_physical_mtu` don't match
- After running `fix-mtu-mismatch.sh` if alarm persists

---

## MTU Troubleshooting Workflow

### Step 1: Diagnose
```bash
bash troubleshooting/diagnose-mtu.sh
```

Review the output to identify:
- Current global MTU settings
- Transport node configuration
- Active alarms

### Step 2: Check VDS MTU in vCenter
**Critical step**: NSX API doesn't show VDS MTU

1. Navigate to vCenter: **Networking → sddc1-cl01-vds01**
2. Right-click → **Edit Settings**
3. Go to **Advanced** tab
4. Note the **Maximum MTU** value

### Step 3: Choose Target MTU
- If VDS MTU = 9000 → Use `9000` (optimal)
- If VDS MTU = 1500-1700 → Use `1700` (minimum recommended)
- **NSX and VDS must match!**

### Step 4: Apply Fix
```bash
# Match NSX to VDS MTU
bash troubleshooting/fix-mtu-mismatch.sh 9000

# If alarm persists, update remote tunnel MTU
bash troubleshooting/fix-remote-tunnel-mtu.sh
```

### Step 5: Verify
1. Check in NSX UI: **System → Fabric → Settings → MTU Configuration Check**
2. Should show "Consistent"
3. Alarm in **System → Alarms** should auto-clear within 5-10 minutes

---

## Common Issues and Solutions

### Issue: "The MTU for VDS switches should not be specified in NSX"
**Cause**: Host switch profile is VDS-backed
**Solution**: This is expected. Configure MTU in vCenter, then update NSX global config to match.

### Issue: Alarm persists after fix
**Cause**: NSX alarm polling delay
**Solution**: Wait 5-10 minutes for auto-clear, or manually resolve in System → Alarms

### Issue: Can't find resync option for transport nodes
**Cause**: NSX 9.0 UI changed from earlier versions
**Solution**: Check **System → Fabric → Settings → MTU Configuration Check** for current status instead

---

## Documentation

Complete investigation and resolution details:
- `nsx-alarms.md` - Full MTU alarm investigation, root cause analysis, and lessons learned

---

## Prerequisites

All scripts require:
- NSX Manager credentials stored in 1Password: `op://Private/nsx01.vcf.lab/password`
- `jq` installed for JSON parsing
- Network access to NSX Manager (nsx01.vcf.lab)
