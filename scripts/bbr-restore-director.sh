#!/usr/bin/env bash
# ABOUTME: Restores the BOSH Director from a BBR backup artifact.
# ABOUTME: Fetches BBR SSH credentials from Ops Manager and restores from a specified backup tar.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() { echo -e "\n${GREEN}==>${NC} ${BLUE}$1${NC}\n"; }
print_info() { echo -e "${YELLOW}i${NC}  $1"; }
print_success() { echo -e "${GREEN}ok${NC} $1"; }
print_error() { echo -e "${RED}!!${NC} $1"; }

DELETE_ARTIFACT=false
ARTIFACT_URL=""

usage() {
    echo "Usage: $0 [options] <backup-artifact.tar>"
    echo "       $0 --artifact-url <s3-url>"
    echo ""
    echo "Restores a BOSH Director from a BBR backup artifact."
    echo ""
    echo "Arguments:"
    echo "  backup-artifact.tar    Path to a local backup tar file"
    echo ""
    echo "Options:"
    echo "  --artifact-url URL     Stream and extract a tar directly from S3 without saving"
    echo "                         it to disk. Only the extracted contents use disk space."
    echo "                         Supports any URL that 'aws s3 cp' accepts."
    echo "  --delete-artifact      Delete the local tar file after extraction to free disk space."
    echo "                         Use when disk is too small to hold both the tar and extracted contents."
    echo ""
    echo "Environment variables (set via .envrc):"
    echo "  BOSH_ENVIRONMENT       BOSH Director URL"
    echo "  OM_TARGET              Ops Manager hostname"
    echo "  OM_USERNAME            Ops Manager username"
    echo "  OM_PASSWORD            Ops Manager password"
    exit 1
}

validate_prerequisites() {
    print_step "Validating Prerequisites"

    local failed=0

    if ! command -v bbr &>/dev/null; then
        print_error "bbr CLI not found. Install with: brew install bbr"
        failed=1
    else
        print_success "bbr found: $(bbr --version)"
    fi

    if ! command -v om &>/dev/null; then
        print_error "om CLI not found. Install with: brew install om"
        failed=1
    else
        print_success "om found: $(om version)"
    fi

    if ! command -v jq &>/dev/null; then
        print_error "jq not found. Install with: brew install jq"
        failed=1
    fi

    if [[ -n "$ARTIFACT_URL" ]] && ! command -v aws &>/dev/null; then
        print_error "aws CLI not found (required for --artifact-url). Install with: brew install awscli"
        failed=1
    fi

    for var in BOSH_ENVIRONMENT OM_TARGET OM_USERNAME OM_PASSWORD; do
        if [[ -z "${!var:-}" ]]; then
            print_error "$var is not set. Source your .envrc first."
            failed=1
        fi
    done

    if [[ $failed -ne 0 ]]; then
        exit 1
    fi

    print_success "All prerequisites met"
}

validate_artifact() {
    print_step "Validating Backup Artifact"

    if [[ -n "$ARTIFACT_URL" ]]; then
        print_info "Artifact URL: $ARTIFACT_URL"
        if ! aws s3 ls "$ARTIFACT_URL" &>/dev/null; then
            print_error "Cannot access S3 artifact: $ARTIFACT_URL"
            print_info "Check your AWS credentials and that the object exists."
            exit 1
        fi
        print_success "S3 artifact accessible"
        return
    fi

    if [[ ! -f "$ARTIFACT_PATH" ]]; then
        print_error "Backup artifact not found: $ARTIFACT_PATH"
        exit 1
    fi

    if ! tar -tf "$ARTIFACT_PATH" &>/dev/null; then
        print_error "Invalid tar file: $ARTIFACT_PATH"
        exit 1
    fi

    print_success "Artifact: $ARTIFACT_PATH"
    # shellcheck disable=SC2012
    print_info "Size: $(ls -lh "$ARTIFACT_PATH" | awk '{print $5}')"
}

fetch_bbr_credentials() {
    print_step "Fetching BBR SSH Credentials from Ops Manager"

    local creds_json
    creds_json=$(om curl -s -p /api/v0/deployed/director/credentials/bbr_ssh_credentials)

    local cred_type
    cred_type=$(echo "$creds_json" | jq -r '.credential.type')

    case "$cred_type" in
        rsa_pkey_credentials)
            BBR_SSH_USER="bbr"
            BBR_SSH_KEY=$(echo "$creds_json" | jq -r '.credential.value.private_key_pem')
            ;;
        simple_credentials)
            BBR_SSH_USER=$(echo "$creds_json" | jq -r '.credential.value.identity')
            BBR_SSH_KEY=$(echo "$creds_json" | jq -r '.credential.value.private_key_pem')
            ;;
        *)
            print_error "Unexpected credential type: $cred_type"
            exit 1
            ;;
    esac

    if [[ -z "$BBR_SSH_KEY" || "$BBR_SSH_KEY" == "null" ]]; then
        print_error "Failed to fetch BBR SSH private key from Ops Manager"
        exit 1
    fi

    BBR_SSH_KEY_PATH=$(mktemp)
    printf '%s\n' "$BBR_SSH_KEY" > "$BBR_SSH_KEY_PATH"
    chmod 600 "$BBR_SSH_KEY_PATH"

    print_success "BBR SSH user: $BBR_SSH_USER"
}

get_director_host() {
    DIRECTOR_HOST="${BOSH_ENVIRONMENT#https://}"
    DIRECTOR_HOST="${DIRECTOR_HOST#http://}"
    DIRECTOR_HOST="${DIRECTOR_HOST%%:*}"
    print_info "Director host: $DIRECTOR_HOST"
}

run_restore() {
    print_step "Running BBR Restore"

    RESTORE_DIR=$(mktemp -d)
    print_info "Extracting artifact to: $RESTORE_DIR"

    if [[ -n "$ARTIFACT_URL" ]]; then
        print_info "Streaming from S3 (tar is never written to disk)..."
        aws s3 cp "$ARTIFACT_URL" - | tar -xvf - -C "$RESTORE_DIR"
    else
        tar -xvf "$ARTIFACT_PATH" -C "$RESTORE_DIR"

        if [[ "$DELETE_ARTIFACT" == true ]]; then
            print_info "Deleting tar artifact to free disk space: $ARTIFACT_PATH"
            rm -f "$ARTIFACT_PATH"
        fi
    fi

    if [[ -n "${BOSH_ALL_PROXY:-}" ]]; then
        print_info "Using SSH proxy: $BOSH_ALL_PROXY"
    fi

    print_info "Starting restore..."

    pushd "$RESTORE_DIR" >/dev/null

    local dirs
    dirs=$(ls -d -- */ 2>/dev/null || true)
    local dir_count
    dir_count=$(echo "$dirs" | grep -c . || true)

    if [[ $dir_count -eq 0 ]]; then
        print_error "No directories found in extracted artifact"
        popd >/dev/null
        exit 1
    elif [[ $dir_count -gt 1 ]]; then
        print_error "Expected one directory in artifact, found $dir_count"
        popd >/dev/null
        exit 1
    fi

    bbr director \
        --host "$DIRECTOR_HOST" \
        --username "$BBR_SSH_USER" \
        --private-key-path "$BBR_SSH_KEY_PATH" \
        restore \
        --artifact-path "$dirs"
    popd >/dev/null

    print_success "Restore completed"
}

cleanup() {
    local exit_code=$?

    if [[ $exit_code -ne 0 && -n "${DIRECTOR_HOST:-}" && -n "${BBR_SSH_USER:-}" && -n "${BBR_SSH_KEY_PATH:-}" ]]; then
        print_error "Restore failed. Running cleanup..."
        bbr director \
            --host "$DIRECTOR_HOST" \
            --username "$BBR_SSH_USER" \
            --private-key-path "$BBR_SSH_KEY_PATH" \
            restore-cleanup || true
    fi

    if [[ -n "${RESTORE_DIR:-}" && -d "${RESTORE_DIR:-}" ]]; then
        print_info "Cleaning up temp directory: $RESTORE_DIR"
        rm -rf "$RESTORE_DIR"
    fi

    if [[ -n "${BBR_SSH_KEY_PATH:-}" && -f "${BBR_SSH_KEY_PATH:-}" ]]; then
        rm -f "$BBR_SSH_KEY_PATH"
    fi
}

trap cleanup EXIT

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --artifact-url)
                if [[ $# -lt 2 || -z "${2:-}" ]]; then
                    print_error "--artifact-url requires a URL argument"
                    usage
                fi
                ARTIFACT_URL="$2"
                shift 2
                ;;
            --delete-artifact)
                DELETE_ARTIFACT=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            -*)
                print_error "Unknown option: $1"
                usage
                ;;
            *)
                ARTIFACT_PATH="$1"
                shift
                ;;
        esac
    done

    if [[ -z "${ARTIFACT_PATH:-}" && -z "$ARTIFACT_URL" ]]; then
        print_error "Must provide either a local tar file or --artifact-url"
        usage
    fi

    if [[ -n "${ARTIFACT_PATH:-}" && -n "$ARTIFACT_URL" ]]; then
        print_error "Cannot use both a local tar file and --artifact-url"
        usage
    fi

    local source="${ARTIFACT_PATH:-$ARTIFACT_URL}"

    print_step "BBR Director Restore"
    print_info "WARNING: This will restore the BOSH Director from a backup."
    print_info "Source: $source"
    print_info "The current director state will be overwritten."
    echo ""
    read -r -p "Are you sure you want to proceed? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        print_info "Restore cancelled."
        exit 0
    fi

    validate_prerequisites
    validate_artifact
    fetch_bbr_credentials
    get_director_host
    run_restore

    print_step "Restore Complete"
    print_success "Director restored successfully from: $source"
    print_info ""
    print_info "Post-restore steps:"
    print_info "1. Verify the director is healthy: bosh env"
    print_info "2. Check deployments: bosh deployments"
    print_info "3. Run a cloud check: bosh -d <deployment> cloud-check"
}

main "$@"
