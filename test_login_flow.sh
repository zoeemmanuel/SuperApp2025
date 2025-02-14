#!/bin/bash

# Configuration
BASE_URL="http://localhost:3000/api/v1"
PHONE="+447389132768"
HANDLE="@zoeemmanuel6"
CSRF_TOKEN="du7lI7t5qRXvq5auD4_UdnqEpFHWDbCc_Gd8hXExSofMiwA5-uEHMXrRLB_SfwfVBPWSYj8pTt4_xlfQcSDt2g"

# Device data
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

# Cookie data
COOKIES="_superapp_session=2Jy5Cllu1Ixm68Y5h%2F%2FDH7K8TUmX%2Blj1XRACOgKomhls7g2PCwtj66apoh9e2Q3xo3Yh9wK%2F628tY1JcesXbdrRtAObSUI1KBgKAOlQda7P8Mmf57%2FD6uXXMAdAAX7HZJsqBBK0aq13HepjgQYQ9SutE1wdcUqcQKhBrOup8H3A%2B4yUAJhKGRNoYfKFiL9O5o74aUoSgZN78wuggEF4o7QXgbfVk23TP9pBcKrYiyDX0qF3FXyK5g5bCSARl66YDGgF1ssWcNg8VPKBD%2FrWMWGZqGE9dAIoVGj9tvGbBHqKBaDQW42U%2Fc1p2kDhf1g9lAgcv7w3a6NsoiRILWRwaJjVIdmDc2oHDJjihj0lUs1hY--KoGKPYF3L6U9dqPc--d1qo3y0nfyr0fbfKPHRVXw%3D%3D"

echo "Starting test flow..."

# Test 1: Check Device
echo "1. Testing Device Check..."
curl -s -X POST "$BASE_URL/auth/check_device" \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -H "X-Device-Data: $DEVICE_DATA" \
  -H "Cookie: $COOKIES" \
  | jq .

# Test 2: Phone Login
echo "2. Testing Phone Login..."
curl -s -X POST "$BASE_URL/auth/phone_login" \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -H "X-Device-Data: $DEVICE_DATA" \
  -H "Cookie: $COOKIES" \
  -d "{\"phone\":\"$PHONE\"}" \
  | jq .

read -p "Enter verification code received: " CODE

# Test 3: Verify Code
echo "3. Testing Code Verification..."
curl -s -X POST "$BASE_URL/auth/verify_code" \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -H "Cookie: $COOKIES" \
  -d "{\"code\":\"$CODE\"}" \
  | jq .

# Test 4: Handle Verification
echo "4. Testing Handle Verification..."
curl -s -X POST "$BASE_URL/auth/handle_verification" \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -H "X-Device-Data: $DEVICE_DATA" \
  -H "Cookie: $COOKIES" \
  -d "{\"handle\":\"$HANDLE\"}" \
  | jq .

# Test 5: Device Status
echo "5. Testing Device Status..."
curl -s -X GET "$BASE_URL/devices/status" \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -H "Cookie: $COOKIES" \
  | jq .

# Test 6: Device Sync
echo "6. Testing Device Sync..."
curl -s -X POST "$BASE_URL/devices/sync" \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -H "Cookie: $COOKIES" \
  | jq .

# Test 7: Reset Devices
echo "7. Testing Device Reset..."
curl -s -X POST "$BASE_URL/devices/reset" \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -H "Cookie: $COOKIES" \
  | jq .
