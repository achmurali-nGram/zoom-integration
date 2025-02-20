#!/bin/bash

# Function to check and install packages
check_and_install_packages() {
    local packages=("jq" "openssl")
    local missing_packages=()

    # Check if we have sudo rights
    if ! command -v sudo &> /dev/null; then
        echo "Error: This script requires sudo privileges to install missing packages." >&2
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
        [ "$VERBOSE" = "true" ] && echo "Installing required packages: ${missing_packages[*]}"
        if [ -f /etc/debian_version ]; then
            # Debian/Ubuntu
            sudo apt-get update
            sudo apt-get install -y "${missing_packages[@]}"
        elif [ -f /etc/redhat-release ]; then
            # CentOS/RHEL
            sudo yum install -y "${missing_packages[@]}"
        else
            echo "Error: Unsupported distribution. Please install ${missing_packages[*]} manually." >&2
            exit 1
        fi
    fi
}

# Parse command line arguments
VERBOSE=false
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --quiet) VERBOSE=false ;;
        -v|--verbose) VERBOSE=true ;;
        *) 
            if [ -z "$MEETING_NUMBER" ]; then
                MEETING_NUMBER="$1"
            elif [ -z "$ROLE" ]; then
                ROLE="$1"
            fi
            ;;
    esac
    shift
done

# Function to validate meeting number
validate_meeting_number() {
    local mn=$1
    if ! [[ "$mn" =~ ^[0-9]+$ ]]; then
        echo "Error: Meeting number must contain only digits" >&2
        exit 1
    fi
}

# Function to validate role
validate_role() {
    local role=$1
    if ! [[ "$role" =~ ^[0-1]$ ]]; then
        echo "Error: Role must be either 0 (participant) or 1 (host)" >&2
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
    echo "Error: .env file not found at $ENV_FILE" >&2
    exit 1
fi

# Check if required environment variables are set
if [ -z "$ZOOM_SDK_KEY" ] || [ -z "$ZOOM_SDK_SECRET" ]; then
    echo "Error: ZOOM_SDK_KEY and ZOOM_SDK_SECRET must be set in .env file" >&2
    exit 1
fi

# Validate inputs
validate_meeting_number "$MEETING_NUMBER"
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
    --arg iat "$TIMESTAMP" \
    '{
        sdkKey: $sdkKey,
        mn: $mn,
        role: ($role|tonumber),
        iat: ($iat|tonumber),
        exp: ($exp|tonumber),
        appKey: $sdkKey,
        tokenExp: ($exp|tonumber)
    }')

# Generate the JWT token using openssl
HEADER=$(echo -n '{"alg":"HS256","typ":"JWT"}' | base64 -w 0 | tr -d '=' | tr '/+' '_-')
PAYLOAD_BASE64=$(echo -n "$PAYLOAD" | base64 -w 0 | tr -d '=' | tr '/+' '_-')
# Create signature using the specified format: HMACSHA256(base64UrlEncode(header) + '.' + base64UrlEncode(payload), secret)
SIGNATURE=$(printf '%s.%s' "$HEADER" "$PAYLOAD_BASE64" | openssl dgst -binary -sha256 -hmac "$ZOOM_SDK_SECRET" | base64 -w 0 | tr -d '=' | tr '/+' '_-')
TOKEN="$HEADER.$PAYLOAD_BASE64.$SIGNATURE"

[ "$VERBOSE" = "true" ] && echo "Generated Zoom Token:"
echo "$TOKEN" 