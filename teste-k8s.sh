BASE="http://fiap-ingress-lb-932060456.us-east-1.elb.amazonaws.com"
API_KEY=""

echo "=== TESTE: Flag desabilitada ==="
curl -s -X PUT $BASE/flags/flags/test-flag \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"is_enabled": false}'
echo ""
sleep 35
curl -s "$BASE/evaluate/evaluate?flag_name=test-flag&user_id=alice"
echo ""

echo ""
echo "=== TESTE: Reabilita a flag ==="
curl -s -X PUT $BASE/flags/flags/test-flag \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"is_enabled": true}'
echo ""

echo ""
echo "=== TESTE: Flag inexistente ==="
curl -s "$BASE/evaluate/evaluate?flag_name=flag-que-nao-existe&user_id=alice"
echo ""

echo ""
echo "=== TESTE: 100% dos usuários ==="
curl -s -X PUT $BASE/targeting/rules/test-flag \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"flag_name": "test-flag", "rules": {"type": "PERCENTAGE", "value": 100}}'
echo ""
sleep 35
for user in alice bob charlie pedro maria; do
  echo -n "$user: "
  curl -s "$BASE/evaluate/evaluate?flag_name=test-flag&user_id=$user" | grep -o '"result":[a-z]*'
done

echo ""
echo "=== TESTE: 0% dos usuários ==="
curl -s -X PUT $BASE/targeting/rules/test-flag \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"flag_name": "test-flag", "rules": {"type": "PERCENTAGE", "value": 0}}'
echo ""
sleep 35
for user in alice bob charlie pedro maria; do
  echo -n "$user: "
  curl -s "$BASE/evaluate/evaluate?flag_name=test-flag&user_id=$user" | grep -o '"result":[a-z]*'
done

echo ""
echo "=== TESTE: Determinismo ==="
curl -s -X PUT $BASE/targeting/rules/test-flag \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"flag_name": "test-flag", "rules": {"type": "PERCENTAGE", "value": 50}}'
sleep 35
for i in 1 2 3; do
  echo -n "alice tentativa $i: "
  curl -s "$BASE/evaluate/evaluate?flag_name=test-flag&user_id=alice" | grep -o '"result":[a-z]*'
done
