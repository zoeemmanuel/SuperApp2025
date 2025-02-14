#!/bin/bash

# Base URL
BASE_URL="http://localhost:3000/api/v1"
CSRF_TOKEN=$(curl -c cookies.txt -s http://localhost:3000/login | grep csrf-token | awk -F'"' '{print $4}')

echo "Testing SuperApp APIs..."
echo "CSRF Token: $CSRF_TOKEN"

# Device data as a variable
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

echo "1. Testing Device Recognition..."
curl -v -X POST "$BASE_URL/auth/check_device" \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -H "X-Device-Data: $DEVICE_DATA" \
  -b cookies.txt

echo -e "\n2. Testing Phone Login..."
curl -v -X POST "$BASE_URL/auth/phone_login" \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -H "X-Device-Data: $DEVICE_DATA" \
  -d '{"phone":"+447389132768"}' \
  -b cookies.txt

echo -e "\n3. Testing Code Verification..."
curl -v -X POST "$BASE_URL/auth/verify_code" \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -d '{"code":"123456"}' \
  -b cookies.txt

echo -e "\n4. Testing Device Reset..."
curl -v -X POST "$BASE_URL/devices/reset" \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -b cookies.txt

echo -e "\n5. Testing Database Status..."
curl -v -X GET "$BASE_URL/devices/status" \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -b cookies.txt

echo -e "\n6. Testing Database Sync..."
curl -v -X POST "$BASE_URL/devices/sync" \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -b cookies.txt
