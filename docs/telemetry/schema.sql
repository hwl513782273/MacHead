-- Cloudflare D1 SQL Schema for MacHead Telemetry
-- Database Binding Name: DB

CREATE TABLE IF NOT EXISTS telemetry_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event TEXT NOT NULL,                  -- 'page_view', 'click_download', 'app_heartbeat', 'app_event'
    anonymous_id TEXT,                    -- client-side anonymous UUID
    app_version TEXT,                     -- e.g. '0.1.14'
    build_number TEXT,                    -- e.g. '18'
    os_version TEXT,                      -- macOS version
    arch TEXT,                            -- 'arm64' or 'x86_64'
    is_headless INTEGER DEFAULT 0,        -- headless mode active (1/0)
    is_launch_at_login INTEGER DEFAULT 0, -- launch-at-login enabled (1/0)
    is_web_dashboard_enabled INTEGER DEFAULT 0, -- web dashboard enabled (1/0)
    auth_accessibility INTEGER DEFAULT 0, -- accessibility permission granted (1/0)
    uptime_seconds INTEGER DEFAULT 0,     -- system uptime in seconds
    utm_source TEXT,                      -- acquisition channel (e.g. v2ex, github, reddit)
    utm_medium TEXT,                      -- medium (e.g. readme, cpc)
    referrer TEXT,                        -- HTTP Referrer of origin
    extra_action TEXT,                    -- 'enable_headless', 'battery_protection_fired', etc.
    country TEXT,                         -- country code (injected by Cloudflare Edge)
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- High-frequency analytics indexes
CREATE INDEX IF NOT EXISTS idx_event_created ON telemetry_events(event, created_at);
CREATE INDEX IF NOT EXISTS idx_anonymous_created ON telemetry_events(anonymous_id, created_at);
CREATE INDEX IF NOT EXISTS idx_utm_source ON telemetry_events(utm_source);
