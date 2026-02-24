-- D1 schema for Kabal crash reporting

CREATE TABLE IF NOT EXISTS crashes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  platform TEXT NOT NULL CHECK(platform IN ('ios', 'backend')),
  app_version TEXT NOT NULL,
  error_name TEXT NOT NULL,
  message TEXT,
  stack_trace TEXT,
  user_id TEXT,
  device_info TEXT,  -- JSON
  context TEXT,       -- JSON (url, user agent, etc)
  timestamp INTEGER NOT NULL,
  status TEXT DEFAULT 'new' CHECK(status IN ('new', 'acknowledged', 'fixing', 'fixed', 'ignored')),
  fix_commit TEXT,
  fix_pr_url TEXT,
  notes TEXT,
  feedback_type TEXT,  -- 'onboarding', 'settings', 'bug_report', 'feature_request', 'general'
  created_at INTEGER DEFAULT (unixepoch()),
  updated_at INTEGER DEFAULT (unixepoch())
);

CREATE INDEX IF NOT EXISTS idx_crashes_platform_version ON crashes(platform, app_version);
CREATE INDEX IF NOT EXISTS idx_crashes_status ON crashes(status);
CREATE INDEX IF NOT EXISTS idx_crashes_timestamp ON crashes(timestamp DESC);

-- For querying new crashes for the cron job
CREATE VIEW IF NOT EXISTS new_crashes AS
SELECT * FROM crashes WHERE status = 'new' ORDER BY timestamp DESC;

-- For tracking fixes
CREATE TABLE IF NOT EXISTS fix_commits (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  crash_id INTEGER REFERENCES crashes(id),
  commit_sha TEXT NOT NULL,
  pr_url TEXT,
  fixed_at INTEGER DEFAULT (unixepoch())
);
