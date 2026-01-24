#!/bin/bash
# ABOUTME: Downloads and uploads TAS tile to Ops Manager
# ABOUTME: Automates product download from Tanzu Network and upload to Ops Manager

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PRODUCT_SLUG="${PRODUCT_SLUG:-cf}"
RELEASE_VERSION="${RELEASE_VERSION:-10.2.5+LTS-T}"
PRODUCT_NAME="${PRODUCT_NAME:-Small Footprint TPCF}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-/tmp}"
LOG_DIR="${LOG_DIR:-/tmp}"
LOG_FILE="${LOG_DIR}/upgrade-tas-$(date +%Y%m%d-%H%M%S).log"

# Setup logging
exec > >(tee -a "$LOG_FILE")
exec 2>&1

# Helper functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')]" "$@"
}
print_step() {
    echo -e "\n${GREEN}==>${NC} ${BLUE}$1${NC}\n"
}

print_info() {
    echo -e "${YELLOW}ℹ${NC}  $1"
}

print_success() {
    echo -e "${GREEN}✓${NC}  $1"
}

print_error() {
    echo -e "${RED}✗${NC}  $1"
}

# Validate prerequisites
validate_prerequisites() {
    print_step "Validating Prerequisites"

    # Check pivnet CLI
    if ! command -v pivnet &> /dev/null; then
        print_error "pivnet CLI not found. Install with: brew tap pivotal-cf/kiln && brew install pivnet-cli"
        exit 1
    fi
    print_success "pivnet CLI found: $(pivnet version)"

    # Check jq
    if ! command -v jq &> /dev/null; then
        print_error "jq not found. Install with: brew install jq"
        exit 1
    fi
    print_success "jq found"

    # Check om CLI
    if ! command -v om &> /dev/null; then
        print_error "om CLI not found. Install with: brew install om"
        exit 1
    fi
    print_success "om CLI found: $(om version)"

    # Check 1Password CLI
    if ! command -v op &> /dev/null; then
        print_error "1Password CLI not found. Install with: brew install 1password-cli"
        exit 1
    fi
    print_success "1Password CLI found"
}

# Get Pivnet token and login
login_pivnet() {
    print_step "Authenticating with Tanzu Network"

    print_info "Fetching Pivnet token from 1Password..."
    PIVNET_TOKEN=$(op read "op://Private/PIVNET_TOKEN/credential" 2>&1)

    if [ -z "$PIVNET_TOKEN" ] || echo "$PIVNET_TOKEN" | grep -q "error"; then
        print_error "Failed to get Pivnet token from 1Password"
        print_info "Error: $PIVNET_TOKEN"
        exit 1
    fi

    print_info "Logging in to Tanzu Network..."
    pivnet login --api-token="$PIVNET_TOKEN"

    print_success "Successfully authenticated with Tanzu Network"
}

# Download TAS product
download_product() {
    print_step "Downloading TAS Product"

    print_info "Product slug: $PRODUCT_SLUG"
    print_info "Release version: $RELEASE_VERSION"
    print_info "Product name: $PRODUCT_NAME"

    # Get product information (single API call, cached)
    print_info "Fetching product information..."
    PRODUCT_INFO=$(pivnet product-files --product-slug="$PRODUCT_SLUG" --release-version="$RELEASE_VERSION" --format json)

    # Parse product details
    PRODUCT_ID=$(echo "$PRODUCT_INFO" | jq -r ".[] | select(.name==\"$PRODUCT_NAME\") | .id")
    AWS_OBJECT_KEY=$(echo "$PRODUCT_INFO" | jq -r ".[] | select(.name==\"$PRODUCT_NAME\") | .aws_object_key")

    # Validate we found the product
    if [ -z "$PRODUCT_ID" ] || [ "$PRODUCT_ID" = "null" ]; then
        print_error "Could not find product: $PRODUCT_NAME"
        print_info "Available products for $RELEASE_VERSION:"
        echo "$PRODUCT_INFO" | jq -r '.[].name'
        exit 1
    fi

    print_success "Found product ID: $PRODUCT_ID"

    # Parse download path
    PRODUCT_FILE=$(basename "$AWS_OBJECT_KEY")
    PRODUCT_FOLDER=$(echo "$AWS_OBJECT_KEY" | cut -d'/' -f1)
    DOWNLOAD_PATH="$DOWNLOAD_DIR/$PRODUCT_FOLDER"

    print_info "Download path: $DOWNLOAD_PATH/$PRODUCT_FILE"

    # Create download directory
    mkdir -p "$DOWNLOAD_PATH"

    # Check if file already exists (idempotency)
    if [ -f "$DOWNLOAD_PATH/$PRODUCT_FILE" ]; then
        print_success "Product already downloaded"
        ls -lh "$DOWNLOAD_PATH/$PRODUCT_FILE"
        print_info "Skipping download (use 'rm $DOWNLOAD_PATH/$PRODUCT_FILE' to force re-download)"
    else
        # Download product (auto-accepts EULA)
        print_info "Downloading product files..."
        pivnet download-product-files \
            --accept-eula \
            --product-slug="$PRODUCT_SLUG" \
            --release-version="$RELEASE_VERSION" \
            --product-file-id="$PRODUCT_ID" \
            -d "$DOWNLOAD_PATH/"

        print_success "Product downloaded successfully"
        ls -lh "$DOWNLOAD_PATH/$PRODUCT_FILE"
    fi

    # Export for next step
    export PRODUCT_FILE
    export DOWNLOAD_PATH
}

# Load Ops Manager credentials
load_om_credentials() {
    print_step "Loading Ops Manager Credentials"

    # Source .envrc if it exists
    ENVRC_PATHS=(
        ".envrc"
        "../.envrc"
        "../../.envrc"
        "$HOME/workspace/tanzu-platform-sbom-service/.envrc"
    )

    for envrc_path in "${ENVRC_PATHS[@]}"; do
        if [ -f "$envrc_path" ]; then
            print_info "Loading credentials from $envrc_path..."
            source "$envrc_path"
            print_success "Credentials loaded"
            break
        fi
    done

    # Verify required variables are set
    if [ -z "$OM_TARGET" ]; then
        print_error "OM_TARGET not set"
        print_info "Please set in .envrc: export OM_TARGET=opsman.example.com"
        exit 1
    fi

    # Add https:// if not present
    if [[ ! "$OM_TARGET" =~ ^https?:// ]]; then
        export OM_TARGET="https://$OM_TARGET"
        print_info "Added https:// to OM_TARGET"
    fi

    if [ -z "$OM_USERNAME" ]; then
        print_error "OM_USERNAME not set"
        print_info "Please set in .envrc: export OM_USERNAME=admin"
        exit 1
    fi

    if [ -z "$OM_PASSWORD" ]; then
        print_error "OM_PASSWORD not set"
        print_info "Please set in .envrc: export OM_PASSWORD=your-password"
        exit 1
    fi

    print_success "Ops Manager credentials verified"
    print_info "Target: $OM_TARGET"
    print_info "Username: $OM_USERNAME"
}

# Upload product to Ops Manager
upload_product() {
    print_step "Uploading Product to Ops Manager"

    print_info "Uploading: $PRODUCT_FILE"
    print_info "Source: $DOWNLOAD_PATH/$PRODUCT_FILE"

    # Check if product is already available (idempotency)
    print_info "Checking if product is already uploaded..."
    EXISTING_PRODUCTS=$(om available-products --format json 2>/dev/null || echo "[]")
    PRODUCT_VERSION=$(echo "$RELEASE_VERSION" | sed 's/+LTS-T//')  # Strip +LTS-T suffix

    # Check if this product version already exists
    if echo "$EXISTING_PRODUCTS" | jq -e ".[] | select(.name == \"cf\") | select(.version | startswith(\"$PRODUCT_VERSION\"))" > /dev/null 2>&1; then
        print_success "Product already available in Ops Manager"
        echo "$EXISTING_PRODUCTS" | jq -r ".[] | select(.name == \"cf\") | select(.version | startswith(\"$PRODUCT_VERSION\")) | \"  Name: \\(.name)\\n  Version: \\(.version)\""
        print_info "Skipping upload (product already available)"
    else
        # Upload using om CLI (uses OM_* environment variables)
        print_info "Uploading new product..."
        om upload-product -p "$DOWNLOAD_PATH/$PRODUCT_FILE"
        print_success "Product uploaded to Ops Manager"
    fi
}

# Verify upload and show next steps
verify_and_summarize() {
    print_step "Upload Complete"

    print_success "TAS tile uploaded successfully"

    print_info ""
    print_info "Next steps:"
    print_info "1. Stage the uploaded product in Ops Manager"
    print_info "2. Configure the product settings"
    print_info "3. Apply changes to deploy the upgrade"
    print_info ""
    print_info "Or use the om CLI:"
    print_info "  om stage-product --product-name cf --product-version <version>"
    print_info "  om apply-changes"
}

# Cleanup on exit
cleanup() {
    if [ $? -ne 0 ]; then
        print_error "Script failed. Downloaded files remain at: $DOWNLOAD_PATH"
    fi
}

trap cleanup EXIT

# Main execution
main() {
    print_step "TAS Tile Upgrade"

    log "Log file: $LOG_FILE"
    print_info "Log file: $LOG_FILE"
    print_info "Tail with: tail -f $LOG_FILE"
    echo ""

    validate_prerequisites
    login_pivnet
    download_product
    load_om_credentials
    upload_product
    verify_and_summarize

    log "Script completed successfully"
}

# Run main function
main "$@"