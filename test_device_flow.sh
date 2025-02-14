#!/bin/bash

# Configuration
BASE_URL="http://167.99.89.187/api/v1"
PHONE="+447389132768"
HANDLE="@zoeemmanuel6"

# Create a device data variable with proper escaping
DEVICE_DATA=$(cat <<EOF
{
  "hardware": {
    "platform": "Linux x86_64",
    "cpuCores": 8,
    "memory": 16,
    "architecture": "x86_64"
  },
  "screen": {
    "width": 1920,
    "height": 1080,
    "pixelRatio": 2
  },
  "gpu": "Intel HD Graphics 630"
}
EOF
)

# Common curl options
CURL_OPTS="-v -H 'Content-Type: application/json' -H 'Accept: application/json'"

echo "Testing device flows..."

# Step 1: Check Device
echo -e "\n1. Checking device..."
curl -X POST "$BASE_URL/auth/check_device" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "{\"device_data\": $DEVICE_DATA}"

# Step 2: Handle Verification
echo -e "\n2. Testing handle verification..."
curl -X POST "$BASE_URL/auth/verify_handle" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "{\"handle\":\"$HANDLE\", \"device_data\": $DEVICE_DATA}"

# Get verification code from user
read -p "Enter verification code (if prompted): " VERIFICATION_CODE

if [ ! -z "$VERIFICATION_CODE" ]; then
  echo -e "\n2b. Submitting verification code..."
  curl -X POST "$BASE_URL/auth/verify_handle_code" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "{\"code\":\"$VERIFICATION_CODE\"}"
fi

# Step 3: Reset Devices
echo -e "\n3. Testing device reset..."
curl -X POST "$BASE_URL/devices/reset" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json"

# Step 4: Check Device Status
echo -e "\n4. Checking device status..."
curl -X GET "$BASE_URL/devices/status" \
  -H "Accept: application/json"

# Step 5: Sync Device
echo -e "\n5. Testing device sync..."
curl -X POST "$BASE_URL/devices/sync" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json"
