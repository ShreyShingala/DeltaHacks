#!/bin/bash

# Comprehensive test suite for /listen endpoint
# Tests various scenarios with different messages and vitals

echo "============================================================"
echo "🧪 API Test Suite - /listen Endpoint"
echo "============================================================"
echo ""

BASE_URL="http://localhost:8000/listen"
TEST_DIR="test_responses"
mkdir -p "$TEST_DIR"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counter
PASSED=0
FAILED=0

# Helper function to run a test
run_test() {
    local test_name="$1"
    local json_data="$2"
    local expected_status="${3:-200}"
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Test: ${test_name}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Create safe filename from test name
    safe_name=$(echo "$test_name" | tr ' ' '_' | tr -cd '[:alnum:]_')
    output_file="${TEST_DIR}/${safe_name}.mp3"
    
    # Make the request
    response=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL" \
        -H "Content-Type: application/json" \
        -d "$json_data" \
        --output "$output_file")
    
    http_code=$(echo "$response" | tail -n 1)
    
    # Check if response is JSON (error) or audio
    if head -c 1 "$output_file" | grep -q '{'; then
        # It's JSON error
        echo -e "${YELLOW}Response:${NC}"
        cat "$output_file"
        echo ""
        if [ "$http_code" = "$expected_status" ]; then
            echo -e "${GREEN}✅ HTTP Status: $http_code (expected)${NC}"
            ((PASSED++))
        else
            echo -e "${RED}❌ HTTP Status: $http_code (expected $expected_status)${NC}"
            ((FAILED++))
        fi
        rm -f "$output_file"
    else
        # It's audio
        file_size=$(wc -c < "$output_file" | tr -d ' ')
        if [ "$file_size" -gt 1000 ] && [ "$http_code" = "$expected_status" ]; then
            echo -e "${GREEN}✅ HTTP Status: $http_code${NC}"
            echo -e "${GREEN}✅ Audio file generated: ${file_size} bytes${NC}"
            echo -e "${BLUE}   Saved to: $output_file${NC}"
            ((PASSED++))
        else
            echo -e "${RED}❌ HTTP Status: $http_code or file too small ($file_size bytes)${NC}"
            ((FAILED++))
        fi
    fi
    echo ""
}

# Test 1: Missing keys (original test)
run_test "1. Missing Keys - Normal Vitals" '{
    "text": "I don'\''t know where my keys are, can you help me?",
    "vitals": {
        "heart_rate": 60,
        "breathing_rate": 10,
        "movement_score": 10,
        "stress_detected": false
    }
}'

# Test 2: Missing keys with stress
run_test "2. Missing Keys - High Stress" '{
    "text": "I can'\''t find my keys! I'\''m late for an appointment!",
    "vitals": {
        "heart_rate": 95,
        "breathing_rate": 20,
        "movement_score": 85,
        "stress_detected": true
    }
}'

# Test 3: Family question
run_test "3. Family Question - Normal" '{
    "text": "When is my daughter coming to visit?",
    "vitals": {
        "heart_rate": 65,
        "breathing_rate": 12,
        "movement_score": 15,
        "stress_detected": false
    }
}'

# Test 4: Family question with stress
run_test "4. Family Question - Stressed" '{
    "text": "I haven'\''t heard from my son in days, I'\''m worried",
    "vitals": {
        "heart_rate": 88,
        "breathing_rate": 18,
        "movement_score": 45,
        "stress_detected": true
    }
}'

# Test 5: Medication reminder
run_test "5. Medication Question - Normal" '{
    "text": "Did I take my medicine today?",
    "vitals": {
        "heart_rate": 70,
        "breathing_rate": 14,
        "movement_score": 20,
        "stress_detected": false
    }
}'

# Test 6: Location question
run_test "6. Location Question - Normal" '{
    "text": "Where am I?",
    "vitals": {
        "heart_rate": 75,
        "breathing_rate": 16,
        "movement_score": 30,
        "stress_detected": false
    }
}'

# Test 7: Location confusion with stress (dementia episode)
run_test "7. Location Confusion - High Stress" '{
    "text": "Where am I? This isn'\''t my house!",
    "vitals": {
        "heart_rate": 100,
        "breathing_rate": 22,
        "movement_score": 90,
        "stress_detected": true
    }
}'

# Test 8: Time question
run_test "8. Time Question - Normal" '{
    "text": "What time is it?",
    "vitals": {
        "heart_rate": 68,
        "breathing_rate": 13,
        "movement_score": 25,
        "stress_detected": false
    }
}'

# Test 9: Appointments
run_test "9. Appointment Question - Normal" '{
    "text": "Do I have any appointments today?",
    "vitals": {
        "heart_rate": 72,
        "breathing_rate": 15,
        "movement_score": 35,
        "stress_detected": false
    }
}'

# Test 10: Lost item (glasses)
run_test "10. Lost Item - Glasses" '{
    "text": "I can'\''t find my reading glasses",
    "vitals": {
        "heart_rate": 65,
        "breathing_rate": 12,
        "movement_score": 40,
        "stress_detected": false
    }
}'

# Test 11: Lost item with stress
run_test "11. Lost Item - Wallet (Stressed)" '{
    "text": "I lost my wallet! Where could it be?",
    "vitals": {
        "heart_rate": 92,
        "breathing_rate": 19,
        "movement_score": 75,
        "stress_detected": true
    }
}'

# Test 12: General help request
run_test "12. General Help - Normal" '{
    "text": "Can you help me with something?",
    "vitals": {
        "heart_rate": 70,
        "breathing_rate": 14,
        "movement_score": 28,
        "stress_detected": false
    }
}'

# Test 13: Calming request (dementia episode)
run_test "13. Calming Request - Very High Stress" '{
    "text": "I'\''m scared, I don'\''t know what'\''s happening",
    "vitals": {
        "heart_rate": 105,
        "breathing_rate": 24,
        "movement_score": 95,
        "stress_detected": true
    }
}'

# Test 14: Memory question
run_test "14. Memory Question - Normal" '{
    "text": "What did I have for breakfast?",
    "vitals": {
        "heart_rate": 68,
        "breathing_rate": 13,
        "movement_score": 22,
        "stress_detected": false
    }
}'

# Test 15: Weather question
run_test "15. Weather Question - Normal" '{
    "text": "What'\''s the weather like today?",
    "vitals": {
        "heart_rate": 72,
        "breathing_rate": 15,
        "movement_score": 30,
        "stress_detected": false
    }
}'

# Test 16: Multiple items lost
run_test "16. Multiple Items Lost - Normal" '{
    "text": "I can'\''t find my keys or my phone",
    "vitals": {
        "heart_rate": 75,
        "breathing_rate": 16,
        "movement_score": 50,
        "stress_detected": false
    }
}'

# Test 17: Reminder request
run_test "17. Reminder Request - Normal" '{
    "text": "Remind me to call my doctor tomorrow",
    "vitals": {
        "heart_rate": 70,
        "breathing_rate": 14,
        "movement_score": 32,
        "stress_detected": false
    }
}'

# Test 18: No vitals (optional field)
run_test "18. No Vitals Provided" '{
    "text": "Hello, how are you?"
}'

# Test 19: Partial vitals
run_test "19. Partial Vitals" '{
    "text": "I need help with something",
    "vitals": {
        "heart_rate": 70,
        "stress_detected": false
    }
}'

# Test 20: Very high heart rate (emergency scenario)
run_test "20. Emergency - Very High Heart Rate" '{
    "text": "I don'\''t feel well",
    "vitals": {
        "heart_rate": 120,
        "breathing_rate": 30,
        "movement_score": 100,
        "stress_detected": true
    }
}'

# Test 21: Simple greeting
run_test "21. Simple Greeting - Normal" '{
    "text": "Good morning!",
    "vitals": {
        "heart_rate": 65,
        "breathing_rate": 12,
        "movement_score": 20,
        "stress_detected": false
    }
}'

# Test 22: Long message
run_test "22. Long Message - Normal" '{
    "text": "I was wondering if you could help me remember where I put my keys and also remind me about my doctor'\''s appointment next week because I really don'\''t want to forget it",
    "vitals": {
        "heart_rate": 72,
        "breathing_rate": 15,
        "movement_score": 35,
        "stress_detected": false
    }
}'

# Test 23: Very low vitals (sleepy)
run_test "23. Low Vitals - Sleepy" '{
    "text": "I'\''m feeling tired",
    "vitals": {
        "heart_rate": 55,
        "breathing_rate": 8,
        "movement_score": 5,
        "stress_detected": false
    }
}'

# Test 24: Shopping list
run_test "24. Shopping List - Normal" '{
    "text": "What should I buy at the grocery store?",
    "vitals": {
        "heart_rate": 68,
        "breathing_rate": 13,
        "movement_score": 25,
        "stress_detected": false
    }
}'

# Test 25: Confusion about day/date
run_test "25. Day/Date Confusion - Stressed" '{
    "text": "What day is it? I'\''m confused",
    "vitals": {
        "heart_rate": 85,
        "breathing_rate": 17,
        "movement_score": 60,
        "stress_detected": true
    }
}'

# Summary
echo ""
echo "============================================================"
echo "📊 Test Summary"
echo "============================================================"
echo -e "${GREEN}✅ Passed: $PASSED${NC}"
echo -e "${RED}❌ Failed: $FAILED${NC}"
echo "Total: $((PASSED + FAILED))"
echo ""
echo "📁 Test responses saved in: $TEST_DIR/"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}⚠️  Some tests failed. Check the output above.${NC}"
    exit 1
fi
