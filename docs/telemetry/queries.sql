-- MacHead Core Growth Metrics SQL Queries
-- Execute these in Cloudflare D1 Console or BI Dashboards

-- 1. North-star metric: weekly continuously-running headless nodes (uptime > 24h)
SELECT COUNT(DISTINCT anonymous_id) AS weekly_active_continuous_headless_nodes
FROM telemetry_events
WHERE event = 'app_heartbeat'
  AND is_headless = 1
  AND uptime_seconds >= 86400
  AND created_at >= datetime('now', '-7 days');

-- 2. Daily active nodes (DAU) and mode ratio
SELECT
    date(created_at) AS report_date,
    COUNT(DISTINCT anonymous_id) AS total_dau,
    COUNT(DISTINCT CASE WHEN is_headless = 1 THEN anonymous_id END) AS headless_dau,
    COUNT(DISTINCT CASE WHEN is_launch_at_login = 1 THEN anonymous_id END) AS auto_launch_dau
FROM telemetry_events
WHERE event = 'app_heartbeat'
GROUP BY report_date
ORDER BY report_date DESC
LIMIT 30;

-- 3. Landing-page acquisition channels and DMG download conversion
SELECT
    COALESCE(utm_source, 'direct') AS source,
    COUNT(CASE WHEN event = 'page_view' THEN 1 END) AS page_views,
    COUNT(CASE WHEN event = 'click_download' THEN 1 END) AS download_clicks,
    ROUND(100.0 * COUNT(CASE WHEN event = 'click_download' THEN 1 END) / NULLIF(COUNT(CASE WHEN event = 'page_view' THEN 1 END), 0), 2) || '%' AS conversion_rate
FROM telemetry_events
WHERE created_at >= datetime('now', '-30 days')
GROUP BY source
ORDER BY page_views DESC;

-- 4. Accessibility permission grant-rate funnel
SELECT
    COUNT(DISTINCT anonymous_id) AS total_active_devices,
    COUNT(DISTINCT CASE WHEN auth_accessibility = 1 THEN anonymous_id END) AS authorized_devices,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN auth_accessibility = 1 THEN anonymous_id END) / COUNT(DISTINCT anonymous_id), 2) || '%' AS auth_success_rate
FROM telemetry_events
WHERE event = 'app_heartbeat';

-- 5. Chip architecture distribution (Apple Silicon vs Intel)
SELECT
    arch,
    COUNT(DISTINCT anonymous_id) AS device_count,
    ROUND(100.0 * COUNT(DISTINCT anonymous_id) / (SELECT COUNT(DISTINCT anonymous_id) FROM telemetry_events WHERE event = 'app_heartbeat'), 2) || '%' AS share
FROM telemetry_events
WHERE event = 'app_heartbeat'
GROUP BY arch;

-- 6. Total battery-protection triggers (core safeguard effectiveness)
SELECT
    COUNT(*) AS total_battery_protections_triggered
FROM telemetry_events
WHERE event = 'app_event' AND extra_action = 'battery_protection_fired';
