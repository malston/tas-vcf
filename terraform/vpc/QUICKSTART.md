# TAS VPC Quick Start Guide

## Step 1: Create VPC via NSX UI (5 minutes)

1. **Navigate**: NSX UI → Networking → VPCs
2. **Click**: "Add VPC"
3. **Configure**:
   ```
   Name: tas-vpc
   Private IPv4 CIDR: 172.20.0.0/16
   VPC External IP Block: 31.31.10.0/24 (select existing)
   Centralized Connectivity Gateway: ✓ Enabled
   Edge Cluster: ec-01
   T0 Gateway: transit-gw
   ```
4. **Save**

## Step 2: Create Three Subnets (5 minutes)

Right-click `tas-vpc` → "New Subnet" (do this 3 times):

### Subnet 1: Infrastructure
```
Name: tas-infrastructure
Type: Private
CIDR: 172.20.1.0/24
Gateway: 172.20.1.1 (auto)
DNS: 192.168.10.2
DHCP: Enabled
```

### Subnet 2: Deployment
```
Name: tas-deployment
Type: Private
CIDR: 172.20.2.0/24
Gateway: 172.20.2.1 (auto)
DNS: 192.168.10.2
DHCP: Enabled
```

### Subnet 3: Services
```
Name: tas-services
Type: Private
CIDR: 172.20.3.0/24
Gateway: 172.20.3.1 (auto)
DNS: 192.168.10.2
DHCP: Enabled
```

## Step 3: Apply Terraform (2 minutes)

```bash
cd /Users/markalston/workspace/tas-vcf/terraform/vpc

# Set NSX password
export TF_VAR_nsxt_password=$(op read "op://Private/nsx01.vcf.lab/password")

# Initialize and apply
terraform init
terraform plan
terraform apply -auto-approve
```

## Step 4: Deploy Test VM (Optional but Recommended)

Test connectivity before deploying Ops Manager:

```bash
cd /Users/markalston/workspace/tas-vcf

# Deploy simple Ubuntu VM to tas-infrastructure subnet
# Use govc or vSphere UI to deploy to VPC subnet
```

In NSX UI:
1. Find deployed VM
2. Right-click → "Assign External IP"
3. Select `31.31.10.15` (test IP)
4. Test SSH: `ssh ubuntu@31.31.10.15`

## Step 5: Deploy Ops Manager to VPC

Once test VM works, deploy Ops Manager:

```bash
# Update deployment script to use VPC subnet instead of NSX-T segment
# Network should be: tas-infrastructure (VPC subnet)
./scripts/deploy-opsman-vpc.sh
```

In NSX UI:
1. Find ops-manager VM
2. Right-click → "Assign External IP"
3. Select `31.31.10.10`
4. Test SSH: `ssh -i ~/.ssh/vcf_opsman_ssh_key ubuntu@31.31.10.10`
5. Test HTTPS: `https://31.31.10.10`

## Verification Checklist

- [ ] VPC `tas-vpc` visible in NSX UI
- [ ] Three subnets created in VPC
- [ ] Terraform apply succeeded
- [ ] Security policies visible in NSX UI (Security → Distributed Firewall)
- [ ] Test VM deployed and SSH works via external IP
- [ ] Ops Manager deployed to VPC subnet
- [ ] Ops Manager SSH accessible via 31.31.10.10
- [ ] Ops Manager HTTPS accessible via 31.31.10.10

## Troubleshooting

### VPC not visible in NSX UI
- Refresh browser
- Check you're in correct project/site

### Terraform can't find VPC
- Verify VPC name exactly matches: `tas-vpc`
- Check NSX credentials: `echo $TF_VAR_nsxt_password`

### External IP assignment doesn't work
- Verify VPC has External IP Block assigned
- Check VM is on VPC subnet (not NSX-T segment)
- Try different IP from block

### SSH still doesn't work after external IP
- This would indicate a different issue than the NSX-T overlay problem
- Check VM firewall: `sudo ufw status`
- Check SSH service: `sudo systemctl status ssh`
- Access via vSphere console to diagnose

## Next Steps

After successful Ops Manager deployment:
1. Configure Ops Manager via web UI
2. Deploy BOSH Director to tas-infrastructure subnet
3. Deploy TAS to tas-deployment subnet
4. Clean up old NSX-T segments (tas-Infrastructure, tas-Deployment, tas-Services)
