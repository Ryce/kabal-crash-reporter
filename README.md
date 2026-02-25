# kabal-crash-reporter

Open-source crash reporting stack for iOS apps:

- **iOS Swift Package** to capture crashes + non-fatal events (depends on **KSCrash 2.5.1**, latest)
- **Cloudflare Worker API** to ingest, deduplicate, and query crash reports
- **Cloudflare D1 schema** for storage
- **Scripts** for symbol upload/download workflow

This is the same mechanism Kabal uses, packaged so other teams can self-host.

## Architecture

```text
[iOS App + KabalCrashReporter SDK]
  -> captures crash + metadata + optional breadcrumbs/feedback
  -> POST /v1/crashes (Worker)

[Cloudflare Worker]
  -> validates API key
  -> computes fingerprint
  -> writes to D1
  -> exposes read API for triage automation

[Automation / Agents]
  -> GET /v1/crashes/new
  -> create fixes, update status via API
```

## Repository layout

- `Package.swift`, `Sources/`, `Tests/` — Swift Package (`KabalCrashReporter`)
- `worker/` — Cloudflare Worker + D1 schema
- `scripts/` — helper scripts (example dSYM flow)

## Quick start

### 1) Deploy Worker

```bash
cd worker
npm install
cp .dev.vars.example .dev.vars
# set API_KEY + optional ADMIN_TOKEN
npx wrangler d1 create kabal_crash_reports
# put DB id into wrangler.toml
npx wrangler d1 execute kabal_crash_reports --file=./schema.sql
npx wrangler deploy
```

### 2) Integrate iOS SDK

Add package from this repo in Xcode (File → Add Packages). The SwiftPM manifest is at repository root (`Package.swift`). Then initialize:

```swift
import KabalCrashReporter

KabalCrashReporterSDK.shared.configure(
  endpoint: URL(string: "https://your-worker.workers.dev")!,
  apiKey: "YOUR_API_KEY",
  appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
  buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
)
```

### 3) Read new crashes

```bash
curl -H "x-api-key: YOUR_API_KEY" \
  "https://your-worker.workers.dev/v1/crashes/new?limit=20"
```

## Security

- Never commit real API keys, tokens, Apple credentials, or DSNs.
- Keep `API_KEY` and `ADMIN_TOKEN` in Worker secrets.
- Rotate keys if leaked.

## License

MIT
