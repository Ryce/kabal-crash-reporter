CREATE TABLE IF NOT EXISTS crash_reports (
  id TEXT PRIMARY KEY,
  app_id TEXT NOT NULL,
  platform TEXT NOT NULL,
  app_version TEXT,
  build_number TEXT,
  os_version TEXT,
  device_model TEXT,
  user_id TEXT,
  fingerprint TEXT NOT NULL,
  title TEXT,
  reason TEXT,
  stack_trace TEXT,
  payload_json TEXT,
  status TEXT NOT NULL DEFAULT new,
  occurrence_count INTEGER NOT NULL DEFAULT 1,
  first_seen_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_crash_reports_status ON crash_reports(status);
CREATE INDEX IF NOT EXISTS idx_crash_reports_last_seen ON crash_reports(last_seen_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_crash_reports_fingerprint_app ON crash_reports(app_id, fingerprint);

CREATE TABLE IF NOT EXISTS crash_feedback (
  id TEXT PRIMARY KEY,
  crash_id TEXT,
  app_id TEXT NOT NULL,
  user_id TEXT,
  message TEXT NOT NULL,
  payload_json TEXT,
  created_at TEXT NOT NULL
);
