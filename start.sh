#!/bin/bash

# Function to validate meeting number
validate_meeting_number() {
    local mn=$1
    if ! [[ "$mn" =~ ^[0-9]+$ ]]; then
        echo "Error: Meeting number must contain only digits"
        return 1
    fi
    return 0
}

# Function to check if .env file exists and has required variables
check_env_file() {
    if [ ! -f .env ]; then
        echo "Error: .env file not found"
        return 1
    fi
    
    required_vars=("ZOOM_SDK_KEY" "ZOOM_SDK_SECRET" "ZOOM_ACCOUNT_ID" "ZOOM_CLIENT_ID" "ZOOM_CLIENT_SECRET")
    missing_vars=()
    
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ $line =~ ^[^#] ]]; then
            eval "export $line"
        fi
    done < .env
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -ne 0 ]; then
        echo "Error: Missing required variables in .env file: ${missing_vars[*]}"
        return 1
    fi
    
    return 0
}

# Check for .env file and required variables
check_env_file || exit 1

# Get meeting number
MEETING_NUMBER=${1:-}
if [ -z "$MEETING_NUMBER" ]; then
    read -p "Enter meeting number: " MEETING_NUMBER
fi

# Validate meeting number
validate_meeting_number "$MEETING_NUMBER" || exit 1

# Get meeting password
MEETING_PASSWORD=${2:-}
if [ -z "$MEETING_PASSWORD" ]; then
    read -p "Enter meeting password: " MEETING_PASSWORD
fi

echo "Generating meeting token..."
TOKEN=$(./scripts/generate-zoom-meeting-token.sh "$MEETING_NUMBER" 1 --quiet | tr -d '\n')
if [ $? -ne 0 ]; then
    echo "Failed to generate meeting token"
    exit 1
fi

echo "Generating recording token..."
RECORDING_TOKEN=$(./scripts/get-recording-token.sh "$MEETING_NUMBER" --quiet | tr -d '\n')
if [ $? -ne 0 ]; then
    echo "Failed to generate recording token"
    exit 1
fi

rm -f demo/config.txt

# Generate config.txt
echo "Creating config.txt..."
cat > demo/config.txt << EOL
meeting_number: "$MEETING_NUMBER"
token: "$TOKEN"
meeting_password: "$MEETING_PASSWORD"
recording_token: "$RECORDING_TOKEN"
GetVideoRawData: "true"
GetAudioRawData: "true"
SendVideoRawData: "true"
SendAudioRawData: "true"
EOL

# Log the config file contents
echo "==============================================="
echo "Generated config.txt with the following contents:"
echo "==============================================="
cat demo/config.txt
echo "==============================================="

echo "Building Docker image..."
docker build -t zoom-sdk-demo -f Dockerfile-Ubuntu/Dockerfile .

echo "Running Docker container..."
docker run -it --rm zoom-sdk-demo 