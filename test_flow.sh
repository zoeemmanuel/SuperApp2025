#!/bin/bash

# Base URL
BASE_URL="http://localhost:3000/api/v1"

# Get CSRF token and cookies
echo "Getting CSRF token..."
CSRF_TOKEN=$(curl -c cookies.txt -s http://localhost:3000/login | grep csrf-token | awk -F'"' '{print $4}')
echo "CSRF Token: $CSRF_TOKEN"

# Device hardware info
DEVICE_DATA='{
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
}'

# Step 1: Check Device
echo "Checking device..."
DEVICE_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/check_device" \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -H "X-Device-Data: $DEVICE_DATA" \
  -b cookies.txt)
echo "Device Response: $DEVICE_RESPONSE"

# If device unknown, do phone verification
if [[ $DEVICE_RESPONSE == *"device_unknown"* ]]; then
  echo "Device unknown, starting phone verification..."
  read -p "Enter phone number (e.g., +447389132768): " PHONE_NUMBER
  
  PHONE_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/phone_login" \
    -H "Content-Type: application/json" \
    -H "X-CSRF-Token: $CSRF_TOKEN" \
    -H "X-Device-Data: $DEVICE_DATA" \
    -d "{\"phone\":\"$PHONE_NUMBER\"}" \
    -b cookies.txt)
  echo "Phone verification response: $PHONE_RESPONSE"
  
  read -p "Enter verification code received: " VERIFICATION_CODE
  
  CODE_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/verify_code" \
    -H "Content-Type: application/json" \
    -H "X-CSRF-Token: $CSRF_TOKEN" \
    -d "{\"code\":\"$VERIFICATION_CODE\"}" \
    -b cookies.txt)
  echo "Code verification response: $CODE_RESPONSE"
fi

# Once authenticated, test device operations
echo "Testing device operations..."

echo "1. Getting device status..."
curl -s -X GET "$BASE_URL/devices/status" \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -b cookies.txt

echo -e "\n2. Syncing device..."
curl -s -X POST "$BASE_URL/devices/sync" \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -b cookies.txt

echo -e "\n3. Resetting other devices..."
curl -s -X POST "$BASE_URL/devices/reset" \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -b cookies.txt
