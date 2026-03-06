#!/usr/bin/env bash
# ABOUTME: Backs up the BOSH Director using BBR (BOSH Backup and Restore).
# ABOUTME: Fetches BBR SSH credentials from Ops Manager and creates a timestamped backup artifact.

set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-$(pwd)/backups}"
ARTIFACT_DIR="${BACKUP_DIR}/director"

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
    echo "$BBR_SSH_KEY" > "$BBR_SSH_KEY_PATH"
    chmod 600 "$BBR_SSH_KEY_PATH"

    print_success "BBR SSH user: $BBR_SSH_USER"
}

get_director_host() {
    # Strip protocol and port from BOSH_ENVIRONMENT
    DIRECTOR_HOST="${BOSH_ENVIRONMENT#https://}"
    DIRECTOR_HOST="${DIRECTOR_HOST#http://}"
    DIRECTOR_HOST="${DIRECTOR_HOST%%:*}"
    print_info "Director host: $DIRECTOR_HOST"
}

run_backup() {
    print_step "Running BBR Backup"

    local current_date
    current_date=$(date +"%Y-%m-%d-%H-%M-%S")

    mkdir -p "$ARTIFACT_DIR"
    print_info "Backup directory: $ARTIFACT_DIR"

    local bbr_args=(
        director
        --host "$DIRECTOR_HOST"
        --username "$BBR_SSH_USER"
        --private-key-path "$BBR_SSH_KEY_PATH"
    )

    # Use BOSH_ALL_PROXY for SSH tunneling through Ops Manager if set
    if [[ -n "${BOSH_ALL_PROXY:-}" ]]; then
        print_info "Using SSH proxy: $BOSH_ALL_PROXY"
    fi

    print_info "Starting backup..."

    pushd "$ARTIFACT_DIR" >/dev/null
    bbr "${bbr_args[@]}" backup

    local artifact_name="director-backup_${current_date}.tar"
    tar -cvf "$artifact_name" --remove-files -- */
    print_success "Backup artifact: $ARTIFACT_DIR/$artifact_name"
    ls -lh "$artifact_name"
    popd >/dev/null
}

cleanup() {
    local exit_code=$?

    if [[ $exit_code -ne 0 && -n "${DIRECTOR_HOST:-}" && -n "${BBR_SSH_USER:-}" ]]; then
        print_error "Backup failed. Running cleanup..."
        pushd "$ARTIFACT_DIR" >/dev/null
        bbr director \
            --host "$DIRECTOR_HOST" \
            --username "$BBR_SSH_USER" \
            --private-key-path "$BBR_SSH_KEY_PATH" \
            backup-cleanup || true
        popd >/dev/null
    fi

    if [[ -n "${BBR_SSH_KEY_PATH:-}" && -f "${BBR_SSH_KEY_PATH:-}" ]]; then
        rm -f "$BBR_SSH_KEY_PATH"
    fi
}

trap cleanup EXIT

main() {
    print_step "BBR Director Backup"

    validate_prerequisites
    fetch_bbr_credentials
    get_director_host
    run_backup

    print_step "Backup Complete"
    print_success "Director backup finished successfully"
}

main "$@"
