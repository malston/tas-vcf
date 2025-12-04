# Network Topology and Routing Configuration

## Overview

This document describes the complete network topology for TAS on VCF 9 deployment, including routing configuration required for external access to VPC workloads.

## Network Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│ External Network (Your Laptop)                                      │
│                                                                      │
│  Laptop: 192.168.2.12                                              │
│     │                                                               │
│     └─► UniFi Router (192.168.2.1)                                 │
│            │                                                         │
│            └─► MikroTik Router (192.168.10.250)                    │
│                   │                                                  │
│                   │ [STATIC ROUTE REQUIRED HERE]                    │
│                   │ 31.31.0.0/16 → 172.30.70.2                     │
│                   │                                                  │
└───────────────────┼──────────────────────────────────────────────────┘
                    │
┌───────────────────┼──────────────────────────────────────────────────┐
│ VCF Infrastructure │                                                  │
│                    │                                                  │
│  Management Network (172.30.0.0/24)                                 │
│  ├─ vCenter: 172.30.0.10                                            │
│  ├─ NSX Manager: 172.30.0.20                                        │
│  ├─ ESXi Hosts:                                                     │
│  │  ├─ esx01: 172.30.0.11                                          │
│  │  ├─ esx02: 172.30.0.12                                          │
│  │  └─ esx03: 172.30.0.13                                          │
│  │                                                                   │
│  NSX Edge Uplink Network (VLAN 70: 172.30.70.0/24)                 │
│  ├─ Upstream Gateway: 172.30.70.1                                  │
│  ├─ Edge Node 01: 172.30.70.2                                      │
│  ├─ Edge Node 02: 172.30.70.3                                      │
│  └─ NSX VPC Gateway: 172.30.70.5 ◄── [ROUTE TARGET]               │
│      │                                                              │
│      └─► T0 Gateway: transit-gw                                    │
│             │                                                        │
│             └─► NSX VPC: tas-vpc                                   │
│                    │                                                 │
│                    ├─ VPC Subnet: tas-infrastructure               │
│                    │  CIDR: 172.20.0.0/24                          │
│                    │  Gateway: 172.20.0.1                          │
│                    │                                                 │
│                    └─ Ops Manager VM                               │
│                       Internal IP: 172.20.0.10                      │
│                       External IP: 31.31.0.11 (VPC auto-assigned)  │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

## Routing Configuration

### UniFi Router (192.168.2.1) - REQUIRED FIRST

**Purpose**: Route 31.31.x.x traffic to MikroTik router

**UniFi Controller Configuration**:
1. Navigate to: Settings → Routing & Firewall → Static Routes
2. Click: Create New Route
3. Configure:
   - Name: `nsx-vpc-via-mikrotik`
   - Destination Network: `31.31.0.0/16`
   - Type: `Next Router` (or `Next Hop`)
   - Next Hop: `192.168.10.250` (MikroTik)
   - Distance: `1`
4. Click: Apply Changes

**Verification**:
```bash
# From your laptop - should show MikroTik as hop 2
traceroute 31.31.0.11
```

### MikroTik Router (192.168.10.250) - REQUIRED SECOND

**Purpose**: Route external VPC IP traffic to NSX VPC Gateway

**CLI Configuration**:
```bash
/ip route add dst-address=31.31.0.0/16 gateway=172.30.70.5 comment="NSX VPC External IPs"
```

**WebFig/WinBox Configuration**:
1. Navigate to: IP → Routes
2. Click: Add New (+)
3. Configure:
   - Dst. Address: `31.31.0.0/16`
   - Gateway: `172.30.70.5`
   - Distance: `1`
   - Comment: `NSX VPC External IPs`
4. Click: OK

**Verification**:
```bash
# On MikroTik
/ip route print where dst-address=31.31.0.0/16

# From your laptop
traceroute 31.31.0.11
# Should show: laptop → UniFi → MikroTik → NSX Edge
```

### NSX T0 Gateway (transit-gw)

**Existing Configuration** (already in place):
- Static Route: `0.0.0.0/0 → 172.30.70.1`
- Uplinks: 172.30.70.2, 172.30.70.3 on VLAN 70
- VPC Gateway: 172.30.70.5 (handles VPC external IPs)
- Connected to: NSX VPC `tas-vpc`

### NSX VPC (tas-vpc)

**External IP Pool**: Auto-assigned by VPC from available range
- Ops Manager: 31.31.0.11 (auto-assigned)
- Additional IPs available: 31.31.0.x range

**VPC Gateway Firewall** (if connectivity still fails after routing):
1. NSX UI → Networking → VPC → tas-vpc → Security
2. Add Gateway Firewall Rule:
   - Name: `allow-opsman-external-access`
   - Source: `Any` (or specific IP range for security)
   - Destination: `31.31.0.11`
   - Services: `SSH (TCP 22)`, `HTTPS (TCP 443)`
   - Action: `Allow`

## Traffic Flow

### Successful Connection Path

```
Laptop (192.168.2.12)
  │
  ├─► DNS: opsman.tas.vcf.lab → 31.31.0.11
  │
  └─► Packet Flow:
        │
        ├─ 1. Send to default gateway (192.168.2.1 - UniFi)
        │
        ├─ 2. UniFi checks routing: 31.31.0.0/16 → 192.168.10.250
        │
        ├─ 3. Packet sent to MikroTik (192.168.10.250)
        │
        ├─ 4. MikroTik checks routing: 31.31.0.0/16 → 172.30.70.5
        │
        ├─ 5. Packet sent to NSX VPC Gateway (172.30.70.5)
        │
        ├─ 6. NSX VPC Gateway routes to VPC (tas-vpc)
        │
        ├─ 7. VPC NATs external IP 31.31.0.11 → internal 172.20.0.10
        │
        └─ 8. Packet delivered to Ops Manager VM
```

### Return Path

```
Ops Manager VM (172.20.0.10)
  │
  ├─ 1. Sends response to source IP (192.168.2.12)
  │
  ├─ 2. VPC NATs source: 172.20.0.10 → 31.31.0.11
  │
  ├─ 3. VPC Gateway (172.30.70.5) routes to MikroTik
  │
  ├─ 4. MikroTik receives and routes to 192.168.2.0/24
  │
  ├─ 5. UniFi delivers to laptop (192.168.2.12)
  │
  └─ 6. TCP connection established
```

## Troubleshooting

### Verify MikroTik Route is Active

```bash
# From your laptop
traceroute 31.31.0.11

# Expected output:
# 1  setup.ui.com (192.168.2.1)
# 2  192.168.10.250
# 3  172.30.70.2 (or timeout if ICMP disabled)
# 4  31.31.0.11

# If going to Comcast, route is not active
```

### Test Connectivity After Route is Added

```bash
# ICMP (ping)
ping -c 3 31.31.0.11

# SSH (port 22)
nc -zv 31.31.0.11 22
# Or
ssh -i ~/.ssh/vcf_opsman_ssh_key ubuntu@31.31.0.11

# HTTPS (port 443)
curl -k https://31.31.0.11
# Or
nc -zv 31.31.0.11 443
```

### Common Issues

#### Issue: Route added but still goes to internet

**Cause**: MikroTik route not active or needs restart

**Fix**:
```bash
# On MikroTik, disable and re-enable the route
/ip route disable [find dst-address=31.31.0.0/16]
/ip route enable [find dst-address=31.31.0.0/16]

# Or restart routing
/system routerboard print
/system reboot
```

#### Issue: Route works but SSH/HTTPS timeout

**Cause**: VPC Gateway Firewall blocking

**Fix**: Add VPC Gateway Firewall allow rule (see NSX VPC section above)

#### Issue: Can ping but cannot SSH

**Cause**: TCP being blocked by firewall while ICMP allowed

**Fix**:
1. Check NSX VPC Gateway Firewall
2. Check NSX Distributed Firewall (Security → Distributed Firewall)
3. Verify SSH service running on VM: `ssh 172.30.0.11` then `ssh 172.20.0.10`

## Network Summary

| Component | IP/Range | Purpose |
|-----------|----------|---------|
| Laptop | 192.168.2.12 | Development workstation |
| UniFi Gateway | 192.168.2.1 | Home network router |
| MikroTik Router | 192.168.10.250 | VCF connectivity router |
| vCenter | 172.30.0.10 | VCF management |
| ESXi Hosts | 172.30.0.11-13 | VCF compute |
| NSX Edge Uplinks | 172.30.70.2-3 | NSX external connectivity |
| NSX VPC Gateway | 172.30.70.5 | VPC external IP routing |
| Upstream Gateway | 172.30.70.1 | T0 default route target |
| VPC Subnet | 172.20.0.0/24 | TAS infrastructure (internal) |
| VPC External IPs | 31.31.0.0/16 | TAS public IPs (external) |
| Ops Manager Internal | 172.20.0.10 | VM IP on VPC subnet |
| Ops Manager External | 31.31.0.11 | VPC-assigned public IP |

## DNS Configuration

Add to your local DNS or `/etc/hosts`:

```
31.31.0.11    opsman.tas.vcf.lab opsman
```

## SSH Configuration

Add to `~/.ssh/config`:

```
Host opsman opsman.tas.vcf.lab
    Hostname 31.31.0.11
    User ubuntu
    IdentityFile ~/.ssh/vcf_opsman_ssh_key
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
```

Then connect with:
```bash
ssh opsman
```

## Next Steps

After successful connectivity:

1. **Access Ops Manager Web UI**: https://31.31.0.11
2. **Complete Initial Setup**: Configure authentication and BOSH Director
3. **Deploy TAS**: Use Ops Manager to deploy Tanzu Application Service
4. **Configure DNS**: Add wildcard DNS for TAS apps domain
5. **Configure Load Balancers**: Set up NSX-T load balancers for TAS components

## References

- [NSX VPC Documentation](https://docs.vmware.com/en/VMware-NSX/index.html)
- [VCF 9.0 VPC Setup Guide](https://williamlam.com/2025/07/ms-a2-vcf-9-0-lab-configuring-nsx-virtual-private-cloud-vpc.html)
- [TAS on vSphere Documentation](https://docs.vmware.com/en/VMware-Tanzu-Application-Service/index.html)
