#!/bin/bash
#
# monit_to_json.sh
# Reads "monit summary -B" output, converts it to JSON and writes
# the result to /var/www/default/htdocs/status.json.
#
# Intended to be run as a cron job every 5 minutes, e.g.:
#   */5 * * * * /path/to/scripts/monit_to_json.sh
#

OUTPUT_FILE="/var/www/default/htdocs/status.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Collect monit output (batch mode, no ANSI colours / box-drawing chars)
MONIT_OUTPUT=$(monit summary -B 2>&1)

if [ $? -ne 0 ]; then
    # Write an error payload so the status page can surface the problem
    cat > "$OUTPUT_FILE" <<JSON
{
  "date": "$TIMESTAMP",
  "error": "monit summary failed",
  "services": []
}
JSON
    exit 1
fi

# Parse the plain-text table produced by "monit summary -B" using Python
# for robust JSON serialisation.
#
# Expected format (fields separated by two or more spaces):
#   Monit x.y.z uptime: ...      <- header, skipped
#                                <- blank line, skipped
#   Service Name   Status  Type  <- column header, skipped
#   ─────────────  ──────  ────  <- separator, skipped
#   nginx          Running Process
#   system_host    Running System
#

echo "$MONIT_OUTPUT" | python3 -c "
import json, sys

timestamp   = '$TIMESTAMP'
output_file = '$OUTPUT_FILE'

raw = sys.stdin.read()
services = []

for line in raw.splitlines():
    s = line.strip()
    if not s:
        continue
    if s.lower().startswith('monit'):
        continue
    if s.lower().startswith('service name') or s.lower().startswith('name'):
        continue
    if s.startswith('\u2500') or s.startswith('-'):
        continue

    # Fields are separated by two or more spaces
    parts = [p for p in s.split('  ') if p.strip()]
    if len(parts) < 2:
        continue

    services.append({
        'name':   parts[0].strip().strip(\"'\\\"\"),
        'status': parts[1].strip(),
        'type':   parts[2].strip() if len(parts) > 2 else 'unknown',
    })

payload = {'date': timestamp, 'services': services}
with open(output_file, 'w') as fh:
    json.dump(payload, fh, indent=2)
"
