#!/bin/bash

# Function to check and install packages
check_and_install_packages() {
    local packages=("jq" "openssl")
    local missing_packages=()

    # Check if we have sudo rights
    if ! command -v sudo &> /dev/null; then
        echo "Error: This script requires sudo privileges to install missing packages."
        exit 1
    fi

    # Check each required package
    for pkg in "${packages[@]}"; do
        if ! command -v "$pkg" &> /dev/null; then
            missing_packages+=("$pkg")
        fi
    done

    # If there are missing packages, try to install them
    if [ ${#missing_packages[@]} -ne 0 ]; then
        echo "Installing required packages: ${missing_packages[*]}"
        if [ -f /etc/debian_version ]; then
            # Debian/Ubuntu
            sudo apt-get update
            sudo apt-get install -y "${missing_packages[@]}"
        elif [ -f /etc/redhat-release ]; then
            # CentOS/RHEL
            sudo yum install -y "${missing_packages[@]}"
        else
            echo "Error: Unsupported distribution. Please install ${missing_packages[*]} manually."
            exit 1
        fi
    fi
}

# Function to validate meeting number
validate_meeting_number() {
    local mn=$1
    # Check if meeting number contains only digits
    if ! [[ "$mn" =~ ^[0-9]+$ ]]; then
        echo "Error: Meeting number must contain only digits"
        exit 1
    fi
}

# Function to validate role
validate_role() {
    local role=$1
    if ! [[ "$role" =~ ^[0-1]$ ]]; then
        echo "Error: Role must be either 0 (participant) or 1 (host)"
        exit 1
    fi
}

# Check and install required packages
check_and_install_packages

# Load environment variables from .env file if it exists
ENV_FILE="$(dirname "$0")/../.env"
if [ -f "$ENV_FILE" ]; then
    export $(cat "$ENV_FILE" | grep -v '#' | xargs)
else
    echo "Error: .env file not found at $ENV_FILE"
    exit 1
fi

# Check if required environment variables are set
if [ -z "$ZOOM_SDK_KEY" ] || [ -z "$ZOOM_SDK_SECRET" ]; then
    echo "Error: ZOOM_SDK_KEY and ZOOM_SDK_SECRET must be set in .env file"
    exit 1
fi

# Get meeting number from argument or prompt
MEETING_NUMBER=${1:-}
if [ -z "$MEETING_NUMBER" ]; then
    read -p "Enter meeting number: " MEETING_NUMBER
fi
validate_meeting_number "$MEETING_NUMBER"

# Get role from argument or default to 0 (participant)
ROLE=${2:-0}
validate_role "$ROLE"

# Current timestamp in seconds
TIMESTAMP=$(date +%s)
# Expiration time (1 hour from now)
EXP=$((TIMESTAMP + 3600))

# Create the payload
PAYLOAD=$(jq -n \
    --arg iss "$ZOOM_SDK_KEY" \
    --arg exp "$EXP" \
    --arg sdkKey "$ZOOM_SDK_KEY" \
    --arg mn "$MEETING_NUMBER" \
    --arg role "$ROLE" \
    '{
        iss: $iss,
        exp: ($exp|tonumber),
        sdkKey: $sdkKey,
        mn: $mn,
        role: ($role|tonumber)
    }')

# Generate the JWT token using openssl
HEADER=$(echo -n '{"alg":"HS256","typ":"JWT"}' | base64 | tr -d '=' | tr '/+' '_-')
PAYLOAD_BASE64=$(echo -n "$PAYLOAD" | base64 | tr -d '=' | tr '/+' '_-')
SIGNATURE=$(echo -n "$HEADER.$PAYLOAD_BASE64" | openssl dgst -binary -sha256 -hmac "$ZOOM_SDK_SECRET" | base64 | tr -d '=' | tr '/+' '_-')
TOKEN="$HEADER.$PAYLOAD_BASE64.$SIGNATURE"

echo "Generated Zoom Token:"
echo "$TOKEN" 