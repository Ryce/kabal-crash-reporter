# Kabal Crash Reporter

Custom crash reporting system for Kabal (iOS + Backend).

## Architecture

```
┌─────────────┐    ┌──────────────────┐    ┌─────────┐
│   iOS App   │───▶│  Cloudflare      │───▶│   D1   │
│  (KSCrash)  │    │  Worker API      │    │ SQLite │
└─────────────┘    └──────────────────┘    └─────────┘
                                     │
┌─────────────┐                      │
│   Backend   │──────────────────────┘
│  (Lambda)   │
└─────────────┘

       │
       ▼
┌─────────────────────────────────────────┐
│  Cron Job (OpenClaw)                    │
│  - Query new crashes                    │
│  - Analyze stack traces                 │
│  - Fix bugs autonomously                │
└─────────────────────────────────────────┘
```

## Setup

### 1. Create D1 Database

```bash
# In the kabal-crash-reporter directory
wrangler d1 create kabal-crashes
# Copy the database_id to wrangler.toml
```

### 2. Apply Schema

```bash
wrangler d1 execute kabal-crashes --file=schema.sql
```

### 3. Deploy Worker

```bash
wrangler deploy
```

### 4. iOS Setup

Add to your `Package.swift` or via SPM in Xcode:

```swift
// Package URL: https://github.com/Ryce/kabal-crash-reporter
// From: https://github.com/Ryce/kabal-crash-reporter/ios
```

In your App delegate:

```swift
import KabalCrashReporter

func application(_ application: UIApplication, 
                 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    
    let config = KabalCrashReporter.Config(
        apiURL: "https://kabal-crash-reporter.<your-subdomain>.workers.dev/crashes",
        appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
        userId: currentUserId  // Optional
    )
    
    KabalCrashReporter(config: config).start()
    
    return true
}
```

### 5. Backend Setup

Add to your Lambda handler:

```typescript
import type { APIGatewayProxyHandler } from 'aws-lambda';

export const handler: APIGatewayProxyHandler = async (event) => {
  try {
    // Your handler logic
    return { statusCode: 200, body: 'OK' };
  } catch (error) {
    // Report to crash reporter
    await fetch('https://kabal-crash-reporter.<your-subdomain>.workers.dev/crashes', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        platform: 'backend',
        app_version: process.env.APP_VERSION,
        error_name: error.name,
        message: error.message,
        stack_trace: error.stack,
        context: {
          requestId: event.requestContext?.requestId,
          path: event.path,
        }
      })
    });
    
    throw error;
  }
};
```

## dSYM Setup (for iOS symbolication)

### Option 1: Xcode Cloud

Add to your Xcode Cloud workflow:

```yaml
# ci_post_clone.sh or similar
- script: |
    cd $CI_ARCHIVE_PRODUCTS_PATH
    for dSYM in $(find . -name "*.dSYM"); do
      echo "Uploading $dSYM..."
      # Upload to R2
    done
  name: Upload dSYMs
```

### Option 2: App Store Connect API

See `scripts/download-dsyms.sh`

## Cron Job (Autonomous Fixes)

Add to OpenClaw via `HEARTBEAT.md` or cron:

```yaml
# cron.yaml
crons:
  - name: crash-reporter
    schedule: "0 * * * *"  # Every hour
    command: |
      # Query new crashes from D1
      wrangler d1 execute kabal-crashes --sql "SELECT * FROM crashes WHERE status = 'new'"
      # For each crash, analyze and fix
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/crashes` | Submit crash report |
| GET | `/crashes` | List crashes (query params: status, platform, limit) |
| GET | `/crashes/new` | Get new crashes for cron |
| PATCH | `/crashes/:id` | Update crash status |
| GET | `/health` | Health check |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `ASC_API_KEY` | App Store Connect API Key |
| `ASC_ISSUER_ID` | App Store Connect Issuer ID |
| `R2_ACCOUNT_ID` | Cloudflare R2 Account ID |
| `R2_ACCESS_KEY` | R2 Access Key |
| `R2_SECRET_KEY` | R2 Secret Key |

## License

Private - Ryce.
