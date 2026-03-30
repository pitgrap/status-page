# Riehemann IT – Status Page

Static status page for Riehemann IT-Consulting that shows the health of monitored
services on two servers. See https://status.riehemann.net/

---

## Repository layout

```
.
├── index.html               # Static status page (GitHub Pages)
├── style.css                # Stylesheet
├── .nojekyll                # Disables Jekyll on GitHub Pages
└── scripts/
    └── monit_to_json.sh     # Cron script – generates status.json
```

---

## Cron script (`scripts/monit_to_json.sh`)

The script runs `monit summary -B`, parses the plain-text output into a JSON
structure, appends a UTC timestamp and writes the result to
`/var/www/default/htdocs/status.json`.

### Setup

1. Make the script executable:
   ```bash
   chmod +x /path/to/scripts/monit_to_json.sh
   ```

2. Add a cron entry (runs every 5 minutes):
   ```cron
   */5 * * * * /path/to/scripts/monit_to_json.sh
   ```

### Requirements

- `monit` must be installed and accessible to the cron user
- `python3` must be available (used for JSON serialisation)

---

## Static status page (GitHub Pages)

`index.html` is a self-contained status page that:

- Fetches `https://server1.riehemann.net/status.json`
- Fetches `https://server2.riehemann.net/status.json`
- Displays each service with a colour-coded status badge
- Auto-refreshes every **5 minutes** (matching the cron interval)
- Shows the timestamp from the last generated JSON file
