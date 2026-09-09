# Extra — Reference Data

Supplementary reference/lookup data, not tied to one track. Unlike `Track N -
*/`, this isn't a hackathon brief — it's code lists a team can join against
whatever track data they're already using (e.g. Track 3's EDI messages
carry SMDG carrier codes and BIC/SMDG facility codes).

## Files

| Path | What it is |
|---|---|
| `smdg-liner-codes.json` | 358 SMDG shipping-line codes — code, name, carrier type, parent company, address |
| `smdg-terminals-with-bfc-sampleset/` | SMDG ocean terminal + BIC Facility Code geofences (sample set). See its own `README.md` for layout, columns, and trust-grade notes. Source: [bic-org/geofence-library](https://github.com/bic-org/geofence-library), snapshot `98452a2`, 2026-09-08 |

## Access

Same as every other folder under `data/` — no separate setup:

- **Dify**: `GET http://data-server/extra/smdg-liner-codes.json` (internal-only, plain text)
- **Open WebUI / Jupyter**: `~/data/extra/...`
- **DeepSeek Harness**: `/workspace/data/extra/...`
