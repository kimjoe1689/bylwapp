CREATE TABLE devices (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    kind TEXT NOT NULL,
    address TEXT NOT NULL UNIQUE,
    model TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE measurements (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id INTEGER NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    type TEXT NOT NULL,
    unit TEXT NOT NULL,
    recorded_at TEXT NOT NULL,
    values_json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    UNIQUE (device_id, type, recorded_at)
);

CREATE INDEX idx_measurements_type_time ON measurements(type, recorded_at);
CREATE INDEX idx_measurements_recorded ON measurements(recorded_at);
