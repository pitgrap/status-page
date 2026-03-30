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
import json, sys, re

timestamp   = '$TIMESTAMP'
output_file = '$OUTPUT_FILE'

# Mapping: lowercase process name -> group label
GROUP_MAP = {
    'apache':            'Web',
    'apache2':           'Web',
    'spamd':             'E-Mail',
    'postfix':           'E-Mail',
    'postgrey':          'E-Mail',
    'dovecot':           'E-Mail',
    'proftpd':           'FTP',
    'mysqld':            'Datenbank',
    'clamav':            'Virenscanner',
    'freshclam':         'Virenscanner',
    'clamav-freshclam':  'Virenscanner',
    'liveconfig':        'Liveconfig',
}

GOOD_STATUSES = {'running', 'ok'}

def status_priority(status):
    \"\"\"Lower number = better; non-OK statuses sort higher so they win.\"\"\"
    return 0 if status.lower() in GOOD_STATUSES else 1

raw = sys.stdin.read()

# group_status maps group_label -> worst status seen so far
group_status = {}

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
    parts = [p for p in re.split(r'  +', s) if p.strip()]
    if len(parts) < 2:
        continue

    name   = parts[0].strip().strip(\"'\\\"\")
    status = parts[1].strip()
    stype  = parts[2].strip().lower() if len(parts) >= 3 else ''

    # Skip filesystem entries
    if stype in ('file', 'directory'):
        continue

    group = GROUP_MAP.get(name.lower(), 'System')

    # Keep the worst (non-OK) status for the group
    if group not in group_status or status_priority(status) > status_priority(group_status[group]):
        group_status[group] = status

# Preserve a deterministic order: known groups first, then System
GROUP_ORDER = ['Web', 'E-Mail', 'FTP', 'Datenbank', 'Virenscanner', 'Liveconfig', 'System']
services = []
for label in GROUP_ORDER:
    if label in group_status:
        services.append({'name': label, 'status': group_status[label]})

payload = {'date': timestamp, 'services': services}
with open(output_file, 'w') as fh:
    json.dump(payload, fh, indent=2)
"
