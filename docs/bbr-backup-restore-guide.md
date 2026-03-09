# BBR Backup and Restore Guide for BOSH Director

This guide covers how to back up and restore your BOSH Director using BBR (BOSH Backup and Restore).

## Prerequisites

### Required CLI Tools

Install the following on the machine where you will run the scripts:

| Tool  | Purpose                                 | Install                                                                                                             |
| ----- | --------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `bbr` | BOSH Backup and Restore CLI             | `brew install bbr` or [GitHub releases](https://github.com/cloudfoundry-incubator/bosh-backup-and-restore/releases) |
| `om`  | Ops Manager CLI                         | `brew install om` or [GitHub releases](https://github.com/pivotal-cf/om/releases)                                   |
| `jq`  | JSON processor                          | `brew install jq` or `apt-get install jq`                                                                           |
| `aws` | AWS CLI (only for S3 streaming restore) | `brew install awscli` or `apt-get install awscli`                                                                   |

### Required Environment Variables

Both scripts require the following environment variables. Set them in a `.envrc` file or export them manually:

```bash
# Ops Manager connection
export OM_TARGET=opsman.example.com
export OM_USERNAME=admin
export OM_PASSWORD=<your-password>
export OM_SKIP_SSL_VALIDATION=true   # if using self-signed certs

# BOSH Director connection (usually set by: eval "$(om bosh-env)")
export BOSH_ENVIRONMENT=<director-ip-or-url>

# SSH proxy through Ops Manager (usually set by: eval "$(om bosh-env)")
export BOSH_ALL_PROXY=ssh+socks5://ubuntu@opsman.example.com:22?private-key=/path/to/key
```

The easiest way to set the BOSH variables is:

```bash
eval "$(om bosh-env)"
```

### Network Connectivity

The machine running these scripts must be able to:

1. Reach Ops Manager on port 443 (for credential retrieval)
2. Reach the BOSH Director on port 22 (for BBR SSH), either directly or through the `BOSH_ALL_PROXY` SSH tunnel

## Backing Up the BOSH Director

### Usage

```bash
./bbr-backup-director.sh
```

### What It Does

1. Validates that all required CLI tools are installed and environment variables are set
2. Fetches BBR SSH credentials from Ops Manager automatically
3. Runs `bbr director backup`
4. Packages the backup into a timestamped tar file
5. Cleans up temporary credentials and BBR state on failure

### Output

The backup artifact is saved to:

```
./backups/director/director-backup_YYYY-MM-DD-HH-MM-SS.tar
```

Override the backup location with the `BACKUP_DIR` environment variable:

```bash
BACKUP_DIR=/mnt/backups ./bbr-backup-director.sh
```

### After the Backup

Upload the tar file to durable storage (e.g., S3):

```bash
aws s3 cp ./backups/director/director-backup_2026-03-06-12-00-00.tar \
  s3://your-bucket/bbr-backups/
```

## Restoring the BOSH Director

### Usage

The restore script supports three modes depending on your disk space constraints.

**Mode 1: Local tar file (default)**

Requires disk space for both the tar file and the extracted contents (roughly 2x the tar size).

```bash
./bbr-restore-director.sh /path/to/director-backup.tar
```

**Mode 2: Local tar file with deletion after extraction**

Deletes the tar file after extraction to free disk space. Peak disk usage is still 2x briefly during extraction.

```bash
./bbr-restore-director.sh --delete-artifact /path/to/director-backup.tar
```

**Mode 3: Stream from S3**

Streams the tar directly from S3 and extracts it without ever writing the tar to disk. Disk usage is only the extracted contents (roughly 1x the tar size). Requires the `aws` CLI with valid credentials.

```bash
./bbr-restore-director.sh --artifact-url s3://your-bucket/bbr-backups/director-backup.tar
```

### Disk Space Requirements

| Mode                | Disk Space Needed    | When to Use          |
| ------------------- | -------------------- | -------------------- |
| Default             | ~2x backup size      | Plenty of disk space |
| `--delete-artifact` | ~2x briefly, then 1x | Moderate disk space  |
| `--artifact-url`    | ~1x backup size      | S3 access available  |

If the Ops Manager VM does not have enough space, attach an extra disk before running the restore. See [Attaching Extra Disk for Restore](#attaching-extra-disk-for-restore-vsphere) below.

### What It Does

1. Prompts for confirmation before proceeding
2. Validates prerequisites and the backup artifact
3. Fetches BBR SSH credentials from Ops Manager
4. Extracts the backup artifact (or streams from S3)
5. Runs `bbr director restore`
6. Cleans up temporary files and credentials

### Before Running a Restore

- Confirm no `bosh deploy` or Ops Manager "Apply Changes" operations are in progress
- Verify that the machine can reach both Ops Manager and the BOSH Director
- If a previous restore attempt failed, the script automatically runs `bbr director restore-cleanup`

### After a Successful Restore

Verify the director is healthy:

```bash
# Check director connectivity
bosh env

# List all deployments
bosh deployments

# Run cloud-check on each deployment to reconcile VM state
bosh -d <deployment-name> cloud-check
```

## Attaching Extra Disk for Restore (vSphere)

The Ops Manager VM typically does not have enough disk space for both the backup tar and the extracted contents. The recommended approach is to attach a temporary disk to the Ops Manager VM in vSphere before running backup or restore operations.

### Attach and Mount

1. In vSphere, add a new hard disk to the Ops Manager VM (size it to at least 2x your expected backup size)
2. SSH into the Ops Manager VM and detect the new disk:

```bash
# Detect the new disk
echo "- - -" | sudo tee /sys/class/scsi_host/host*/scan

# Find it (likely /dev/sdb)
lsblk

# Create filesystem and mount
sudo mkfs.ext4 /dev/sdb
sudo mkdir -p /mnt/bbr
sudo mount /dev/sdb /mnt/bbr
```

### Run Backup or Restore on the Mounted Disk

For backups, point `BACKUP_DIR` at the mounted disk:

```bash
BACKUP_DIR=/mnt/bbr ./bbr-backup-director.sh
```

For restores, set `TMPDIR` so the restore script extracts to the mounted disk:

```bash
export TMPDIR=/mnt/bbr
./bbr-restore-director.sh /mnt/bbr/director-backup.tar
```

### Detach After Backup or Restore

```bash
sudo umount /mnt/bbr
sudo sync
echo 1 | sudo tee /sys/block/sdb/device/delete
```

Then remove the disk from the VM in vSphere.

## Troubleshooting

### "failed reading private key: bad file descriptor"

The BBR CLI cannot read the SSH private key. This is handled by the scripts (they write the key to a temp file), but if you see this error, check that `/tmp` has available space and is writable.

### "bbr-backup already exists on the director"

A previous backup was interrupted. Run cleanup manually:

```bash
bbr director \
  --host <director-ip> \
  --username bbr \
  --private-key-path /path/to/key \
  backup-cleanup
```

Or simply re-run the backup script. On failure, it runs cleanup automatically.

### Ops Manager credential fetch fails

Verify your `OM_TARGET`, `OM_USERNAME`, and `OM_PASSWORD` are correct:

```bash
om curl -s -p /api/v0/deployed/director/credentials/bbr_ssh_credentials | jq .credential.type
```

This should return `rsa_pkey_credentials` or `simple_credentials`.

### Restore fails with "already exists"

A previous restore was interrupted. Run cleanup:

```bash
bbr director \
  --host <director-ip> \
  --username bbr \
  --private-key-path /path/to/key \
  restore-cleanup
```

The restore script runs this automatically on failure, but you may need to run it manually if the script itself was killed.
