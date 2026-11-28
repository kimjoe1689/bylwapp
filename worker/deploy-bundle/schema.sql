-- 0001_init.sql
CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('admin', 'caregiver')),
    created_at TEXT NOT NULL
);

CREATE TABLE sessions (
    token_hash TEXT PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at TEXT NOT NULL
);

CREATE TABLE devices (
    device_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    created_at TEXT NOT NULL
);

CREATE TABLE device_tokens (
    token_hash TEXT PRIMARY KEY,
    device_id TEXT NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
    created_at TEXT NOT NULL,
    revoked_at TEXT
);

CREATE TABLE events (
    device_id TEXT NOT NULL,
    event_id TEXT NOT NULL,
    payload_hash TEXT NOT NULL,
    canonical_json TEXT NOT NULL,
    server_received_at TEXT NOT NULL,
    measurement_type TEXT NOT NULL,
    unit TEXT NOT NULL,
    sensor_address TEXT NOT NULL,
    sensor_kind TEXT NOT NULL,
    sensor_model TEXT NOT NULL,
    monotonic_us INTEGER NOT NULL,
    wall_time_utc TEXT,
    clock_state TEXT NOT NULL,
    operating_state TEXT NOT NULL,
    values_json TEXT NOT NULL,
    PRIMARY KEY (device_id, event_id)
);

CREATE INDEX idx_events_received ON events(server_received_at DESC);
CREATE INDEX idx_events_type ON events(measurement_type, server_received_at DESC);

CREATE TABLE ingest_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id TEXT NOT NULL,
    event_id TEXT NOT NULL,
    result TEXT NOT NULL CHECK (result IN ('stored', 'duplicate', 'conflict')),
    presented_hash TEXT NOT NULL,
    stored_hash TEXT NOT NULL,
    at TEXT NOT NULL
);

CREATE INDEX idx_ingest_result ON ingest_log(result, at DESC);

CREATE TABLE ground_truth (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id TEXT NOT NULL,
    match_key TEXT NOT NULL,
    reference_type TEXT NOT NULL,
    reference_value TEXT NOT NULL,
    observed_at TEXT NOT NULL,
    observer TEXT NOT NULL,
    notes TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL
);

-- 0002_pairing.sql
CREATE TABLE pairing_codes (
    code TEXT PRIMARY KEY,
    device_id TEXT NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
    expires_at TEXT NOT NULL,
    used_at TEXT,
    created_at TEXT NOT NULL
);

CREATE INDEX idx_pairing_device ON pairing_codes(device_id, created_at DESC);
