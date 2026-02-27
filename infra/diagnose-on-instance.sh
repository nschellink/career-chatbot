#!/bin/bash
# Run this ON THE EC2 INSTANCE (e.g. via SSM Session Manager) to see why the app might not respond.
# Paste the output when asking for help.
set -e
echo "=== 1. career-chatbot service ==="
systemctl is-active career-chatbot 2>/dev/null || true
systemctl is-enabled career-chatbot 2>/dev/null || true
echo ""
echo "=== 2. Gradio on 7860 (expect 200) ==="
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://127.0.0.1:7860/ 2>/dev/null || echo "Connection failed"
echo ""
echo "=== 3. Caddy on 80 (expect 200) ==="
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://127.0.0.1:80/ 2>/dev/null || echo "Connection failed"
echo ""
echo "=== 4. Last career-chatbot log lines ==="
journalctl -u career-chatbot -n 15 --no-pager 2>/dev/null || true
echo ""
echo "=== 5. Listening ports ==="
ss -tlnp 2>/dev/null | grep -E ':80|:7860' || true
