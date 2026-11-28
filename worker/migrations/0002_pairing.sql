CREATE TABLE pairing_codes (
    code TEXT PRIMARY KEY,
    device_id TEXT NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
    expires_at TEXT NOT NULL,
    used_at TEXT,
    created_at TEXT NOT NULL
);

CREATE INDEX idx_pairing_device ON pairing_codes(device_id, created_at DESC);
