#!/bin/bash

# Function to check and install packages
check_and_install_packages() {
    local packages=("jq" "curl")
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
        *) MEETING_ID="$1" ;;
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

# Load environment variables from .env file
ENV_FILE="$(dirname "$0")/../.env"
if [ -f "$ENV_FILE" ]; then
    export $(cat "$ENV_FILE" | grep -v '#' | xargs)
else
    echo "Error: .env file not found at $ENV_FILE" >&2
    exit 1
fi

# Check if required environment variables are set
if [ -z "$ZOOM_ACCOUNT_ID" ] || [ -z "$ZOOM_CLIENT_ID" ] || [ -z "$ZOOM_CLIENT_SECRET" ]; then
    echo "Error: Required environment variables are not set" >&2
    echo "Please make sure ZOOM_ACCOUNT_ID, ZOOM_CLIENT_ID, and ZOOM_CLIENT_SECRET are set in .env file" >&2
    exit 1
fi

# Validate meeting number
validate_meeting_number "$MEETING_ID"

# Check and install required packages
check_and_install_packages

# Function to get access token using S2S authentication
get_access_token() {
    local auth_string=$(echo -n "$ZOOM_CLIENT_ID:$ZOOM_CLIENT_SECRET" | base64)
    
    response=$(curl -s -X POST "https://zoom.us/oauth/token" \
        -H "Authorization: Basic $auth_string" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=account_credentials&account_id=$ZOOM_ACCOUNT_ID")
    
    # Check if jq command succeeded and response contains access_token
    if ! access_token=$(echo "$response" | jq -r '.access_token' 2>/dev/null) || [ "$access_token" = "null" ]; then
        echo "Error: Failed to get access token" >&2
        echo "Response: $response" >&2
        exit 1
    fi
    
    echo "$access_token"
}

# Function to get recording token
get_recording_token() {
    local access_token=$1
    local meeting_id=$2
    
    response=$(curl -s -X GET "https://api.zoom.us/v2/meetings/$meeting_id/jointoken/local_recording?bypass_waiting_room=true" \
        -H "Authorization: Bearer $access_token")
    
    # Check if jq command succeeded and response contains token
    if ! recording_token=$(echo "$response" | jq -r '.token' 2>/dev/null) || [ "$recording_token" = "null" ]; then
        echo "Error: Failed to get recording token" >&2
        echo "Response: $response" >&2
        exit 1
    fi
    
    echo "$recording_token"
}

# Main execution
[ "$VERBOSE" = "true" ] && echo "Getting access token..."
access_token=$(get_access_token)
[ "$VERBOSE" = "true" ] && echo "Access token obtained successfully"
[ "$VERBOSE" = "true" ] && echo "Getting recording token for meeting ID: $MEETING_ID"
recording_token=$(get_recording_token "$access_token" "$MEETING_ID")
echo "$recording_token" 