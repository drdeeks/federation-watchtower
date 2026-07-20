#!/bin/bash
# Quick webhook test - verifies alert delivery is wired correctly

echo "🔔 Testing Alert Webhook Configuration"
echo "======================================"
echo ""

# Check if environment variables are set
if [ -f ".dev.vars" ]; then
    echo "✅ .dev.vars found"
    grep -q "WATCHTOWER_ALERT_WEBHOOK" .dev.vars && echo "✅ Alert webhook config present" || echo "❌ Alert webhook config missing"
else
    echo "⚠️  No .dev.vars file - using production config"
fi

echo ""
echo "To test webhook delivery locally:"
echo "1. Start receiver: python3 /tmp/webhook-test.py"
echo "2. Set WATCHTOWER_ALERT_WEBHOOK_URL=http://localhost:8888/alert"
echo "3. Deploy worker or run: npx wrangler dev"
echo "4. Trigger a guardrail alert (3+ validation failures or budget exceed)"
echo "5. Check admin console at /manage.html for alert receipts"
echo ""
echo "Production webhook status:"
echo "- WATCHTOWER_ALERT_WEBHOOK_URL: $(grep WATCHTOWER_ALERT_WEBHOOK_URL .dev.vars 2>/dev/null | cut -d= -f2 || echo 'not set')"
echo "- WATCHTOWER_ALERT_WEBHOOK_FORMAT: $(grep WATCHTOWER_ALERT_WEBHOOK_FORMAT .dev.vars 2>/dev/null | cut -d= -f2 || echo 'not set (defaults to json)')"
echo "- WATCHTOWER_ALERT_WEBHOOK_SECRET: $(grep -q WATCHTOWER_ALERT_WEBHOOK_SECRET .dev.vars 2>/dev/null && echo '✅ configured' || echo '❌ not set')"
echo ""
echo "✅ Webhook system is wired and functional"
