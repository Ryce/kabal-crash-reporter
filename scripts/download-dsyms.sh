#!/bin/bash
#
# download-dsyms.sh
# Downloads dSYM files from App Store Connect after a build
#
# Usage: ./download-dsyms.sh <build_id> <app_version>
# 
# Environment variables:
#   ASC_API_KEY     - App Store Connect API Key ID
#   ASC_ISSUER_ID   - App Store Connect Issuer ID  
#   R2_ACCOUNT_ID   - Cloudflare R2 Account ID
#   R2_ACCESS_KEY  - R2 Access Key
#   R2_SECRET_KEY  - R2 Secret Key
#   R2_BUCKET      - R2 Bucket name (e.g., kabal-dsyms)
#

set -e

BUILD_ID="${1}"
APP_VERSION="${2}"

if [ -z "$BUILD_ID" ] || [ -z "$APP_VERSION" ]; then
    echo "Usage: $0 <build_id> <app_version>"
    exit 1
fi

echo "[INFO] Downloading dSYMs for build $BUILD_ID (version $APP_VERSION)"

# Get JWT from App Store Connect
get_asc_token() {
    local now
    now=$(date +%s)
    
    local payload
    payload=$(cat <<EOF
{
  "iss": "$ASC_ISSUER_ID",
  "iat": $now,
  "exp": $((now + 1200)),
  "aud": "appstoreconnect-v1"
}
EOF
)
    
    # Sign with ASC API Key (requires private key)
    # Note: You'll need to set up ASC_PRIVATE_KEY as a base64-encoded p8 file
    # or store it in keychain and retrieve it here
    
    echo "ERROR: ASC token generation not implemented"
    echo "Please set up ASC_PRIVATE_KEY environment variable with your p8 private key"
    exit 1
}

# Alternative: Use Apple's ascld if available
download_dsyms_asc() {
    echo "[INFO] Using App Store Connect to download dSYMs..."
    
    # This requires Xcode 15+ with asc command line tool
    if command -v asc &> /dev/null; then
        asc dsym download --build-id "$BUILD_ID" --output "./dSYMs"
    else
        echo "[ERROR] 'asc' command not found. Install Xcode 15+ or set up ASC API manually"
        exit 1
    fi
}

# Alternative: Use fastlane match or pilot
download_dsyms_fastlane() {
    echo "[INFO] Using fastlane to download dSYMs..."
    
    if [ -f "./Fastfile" ]; then
        bundle exec fastlane download_dsyms build_number:"$BUILD_ID"
    else
        echo "[ERROR] Fastfile not found"
        exit 1
    fi
}

# Upload to Cloudflare R2
upload_to_r2() {
    local file="${1}"
    local key="app-${APP_VERSION}.zip"
    
    echo "[INFO] Uploading to R2: $key"
    
    # Using wrangler
    if command -v wrangler &> /dev/null; then
        wrangler r2 object put "$R2_BUCKET/$key" --file="$file"
    else
        # Fallback: use AWS CLI with R2 (S3-compatible)
        aws s3 cp "$file" "s3://$R2_BUCKET/$key" \
            --endpoint-url="https://$R2_ACCOUNT_ID.r2.cloudflarestorage.com" \
            --region="auto"
    fi
}

# Main
main() {
    # Create temp directory
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Try to download dSYMs
    if ! download_dsyms_asc; then
        echo "[WARN] ASC download failed, trying fastlane..."
        download_dsyms_fastlane
    fi
    
    # Check if we got dSYMs
    if [ ! -d "dSYMs" ] || [ -z "$(ls -A dSYMs 2>/dev/null)" ]; then
        echo "[ERROR] No dSYMs found"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # Create ZIP
    ZIP_FILE="dSYMs-${APP_VERSION}.zip"
    zip -r "$ZIP_FILE" dSYMs/
    
    # Upload to R2
    upload_to_r2 "$ZIP_FILE"
    
    # Cleanup
    rm -rf "$TEMP_DIR"
    
    echo "[SUCCESS] dSYMs for $APP_VERSION uploaded"
}

main
