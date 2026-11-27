// Package store persists devices and health measurements in SQLite.
package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

// ErrNotFound is returned when a row does not exist.
var ErrNotFound = errors.New("not found")

// Device is a BLE health device known to the admin server.
type Device struct {
	ID        int64     `json:"id"`
	Name      string    `json:"name"`
	Kind      string    `json:"kind"`
	Address   string    `json:"address"`
	Model     string    `json:"model"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// Measurement is one uploaded health sample.
type Measurement struct {
	ID            int64           `json:"id"`
	DeviceID      int64           `json:"device_id"`
	DeviceName    string          `json:"device_name"`
	DeviceAddress string          `json:"device_address"`
	DeviceKind    string          `json:"device_kind"`
	DeviceModel   string          `json:"device_model"`
	Type          string          `json:"type"`
	Unit          string          `json:"unit"`
	RecordedAt    time.Time       `json:"recorded_at"`
	Values        json.RawMessage `json:"values"`
	CreatedAt     time.Time       `json:"created_at"`
}

// MeasurementInput is the payload used to insert a measurement.
type MeasurementInput struct {
	Type       string
	Unit       string
	RecordedAt time.Time
	Values     json.RawMessage
}

// MeasurementFilter narrows list queries.
type MeasurementFilter struct {
	DeviceID *int64
	Type     string
	From     *time.Time
	To       *time.Time
	Limit    int
}

// SyncResult reports how a batch upload was applied.
type SyncResult struct {
	DeviceID int64 `json:"device_id"`
	Inserted int   `json:"inserted"`
	Skipped  int   `json:"skipped"`
}

// Store is a SQLite-backed repository.
type Store struct {
	db *sql.DB
}

// Open creates parent directories and opens the database.
func Open(path string) (*Store, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, fmt.Errorf("create db directory: %w", err)
	}
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	var mode string
	if err := db.QueryRow(`PRAGMA journal_mode = WAL`).Scan(&mode); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("enable wal: %w", err)
	}
	if _, err := db.Exec(`PRAGMA foreign_keys = ON`); err != nil {
		_ = db.Close()
		return nil, err
	}
	if _, err := db.Exec(`PRAGMA busy_timeout = 5000`); err != nil {
		_ = db.Close()
		return nil, err
	}
	if err := db.Ping(); err != nil {
		_ = db.Close()
		return nil, err
	}
	return &Store{db: db}, nil
}

// Close closes the database.
func (s *Store) Close() error { return s.db.Close() }

// Ping checks that the database is reachable.
func (s *Store) Ping(ctx context.Context) error { return s.db.PingContext(ctx) }

// DB exposes the handle for migrations.
func (s *Store) DB() *sql.DB { return s.db }

// UpsertDevice inserts a device or updates its name, kind, and model by address.
func (s *Store) UpsertDevice(ctx context.Context, name, kind, address, model string) (Device, error) {
	now := formatTime(time.Now())
	row := s.db.QueryRowContext(ctx, `
		INSERT INTO devices(name, kind, address, model, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?)
		ON CONFLICT(address) DO UPDATE SET
			name = excluded.name,
			kind = excluded.kind,
			model = excluded.model,
			updated_at = excluded.updated_at
		RETURNING id, name, kind, address, model, created_at, updated_at
	`, name, kind, address, model, now, now)
	return scanDevice(row)
}

// CreateDevice inserts a device and rejects a duplicate address.
func (s *Store) CreateDevice(ctx context.Context, name, kind, address, model string) (Device, error) {
	now := formatTime(time.Now())
	row := s.db.QueryRowContext(ctx, `
		INSERT INTO devices(name, kind, address, model, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?)
		RETURNING id, name, kind, address, model, created_at, updated_at
	`, name, kind, address, model, now, now)
	device, err := scanDevice(row)
	if err != nil && strings.Contains(err.Error(), "UNIQUE") {
		return Device{}, fmt.Errorf("device address already exists")
	}
	return device, err
}

// UpdateDevice changes mutable device fields.
func (s *Store) UpdateDevice(ctx context.Context, id int64, name, kind, model string) (Device, error) {
	row := s.db.QueryRowContext(ctx, `
		UPDATE devices
		SET name = ?, kind = ?, model = ?, updated_at = ?
		WHERE id = ?
		RETURNING id, name, kind, address, model, created_at, updated_at
	`, name, kind, model, formatTime(time.Now()), id)
	device, err := scanDevice(row)
	if errors.Is(err, sql.ErrNoRows) {
		return Device{}, ErrNotFound
	}
	return device, err
}

// GetDevice loads one device.
func (s *Store) GetDevice(ctx context.Context, id int64) (Device, error) {
	row := s.db.QueryRowContext(ctx, `
		SELECT id, name, kind, address, model, created_at, updated_at
		FROM devices WHERE id = ?
	`, id)
	device, err := scanDevice(row)
	if errors.Is(err, sql.ErrNoRows) {
		return Device{}, ErrNotFound
	}
	return device, err
}

// ListDevices returns devices ordered by most recently updated.
func (s *Store) ListDevices(ctx context.Context) ([]Device, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, name, kind, address, model, created_at, updated_at
		FROM devices ORDER BY updated_at DESC, id DESC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Device
	for rows.Next() {
		device, err := scanDevice(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, device)
	}
	if out == nil {
		out = []Device{}
	}
	return out, rows.Err()
}

// DeleteDevice removes a device and its measurements.
func (s *Store) DeleteDevice(ctx context.Context, id int64) error {
	res, err := s.db.ExecContext(ctx, `DELETE FROM devices WHERE id = ?`, id)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return ErrNotFound
	}
	return nil
}

// CreateMeasurement inserts one measurement for an existing device.
func (s *Store) CreateMeasurement(ctx context.Context, deviceID int64, in MeasurementInput) (Measurement, error) {
	if _, err := s.GetDevice(ctx, deviceID); err != nil {
		return Measurement{}, err
	}
	res, err := s.db.ExecContext(ctx, `
		INSERT INTO measurements(device_id, type, unit, recorded_at, values_json, created_at)
		VALUES (?, ?, ?, ?, ?, ?)
	`, deviceID, in.Type, in.Unit, formatTime(in.RecordedAt), string(in.Values), formatTime(time.Now()))
	if err != nil {
		if strings.Contains(err.Error(), "UNIQUE") {
			return Measurement{}, fmt.Errorf("measurement already exists")
		}
		return Measurement{}, err
	}
	id, err := res.LastInsertId()
	if err != nil {
		return Measurement{}, err
	}
	return s.GetMeasurement(ctx, id)
}

// SyncDeviceMeasurements upserts the device and inserts measurements, skipping duplicates.
func (s *Store) SyncDeviceMeasurements(ctx context.Context, name, kind, address, model string, items []MeasurementInput) (SyncResult, error) {
	device, err := s.UpsertDevice(ctx, name, kind, address, model)
	if err != nil {
		return SyncResult{}, err
	}
	result := SyncResult{DeviceID: device.ID}
	for _, item := range items {
		res, err := s.db.ExecContext(ctx, `
			INSERT INTO measurements(device_id, type, unit, recorded_at, values_json, created_at)
			VALUES (?, ?, ?, ?, ?, ?)
			ON CONFLICT(device_id, type, recorded_at) DO NOTHING
		`, device.ID, item.Type, item.Unit, formatTime(item.RecordedAt), string(item.Values), formatTime(time.Now()))
		if err != nil {
			return SyncResult{}, err
		}
		n, err := res.RowsAffected()
		if err != nil {
			return SyncResult{}, err
		}
		if n == 0 {
			result.Skipped++
		} else {
			result.Inserted++
		}
	}
	return result, nil
}

// GetMeasurement loads one measurement.
func (s *Store) GetMeasurement(ctx context.Context, id int64) (Measurement, error) {
	row := s.db.QueryRowContext(ctx, measurementSelect+` WHERE m.id = ?`, id)
	item, err := scanMeasurement(row)
	if errors.Is(err, sql.ErrNoRows) {
		return Measurement{}, ErrNotFound
	}
	return item, err
}

// ListMeasurements returns measurements matching the filter, newest first.
func (s *Store) ListMeasurements(ctx context.Context, filter MeasurementFilter) ([]Measurement, error) {
	limit := filter.Limit
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	query := measurementSelect + ` WHERE 1=1`
	args := make([]any, 0, 5)
	if filter.DeviceID != nil {
		query += ` AND m.device_id = ?`
		args = append(args, *filter.DeviceID)
	}
	if filter.Type != "" {
		query += ` AND m.type = ?`
		args = append(args, filter.Type)
	}
	if filter.From != nil {
		query += ` AND m.recorded_at >= ?`
		args = append(args, formatTime(*filter.From))
	}
	if filter.To != nil {
		query += ` AND m.recorded_at <= ?`
		args = append(args, formatTime(*filter.To))
	}
	query += ` ORDER BY m.recorded_at DESC, m.id DESC LIMIT ?`
	args = append(args, limit)
	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Measurement{}
	for rows.Next() {
		item, err := scanMeasurement(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, item)
	}
	return out, rows.Err()
}

// UpdateMeasurement replaces the sample fields of one measurement.
func (s *Store) UpdateMeasurement(ctx context.Context, id int64, in MeasurementInput) (Measurement, error) {
	res, err := s.db.ExecContext(ctx, `
		UPDATE measurements
		SET type = ?, unit = ?, recorded_at = ?, values_json = ?
		WHERE id = ?
	`, in.Type, in.Unit, formatTime(in.RecordedAt), string(in.Values), id)
	if err != nil {
		if strings.Contains(err.Error(), "UNIQUE") {
			return Measurement{}, fmt.Errorf("measurement already exists")
		}
		return Measurement{}, err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return Measurement{}, err
	}
	if n == 0 {
		return Measurement{}, ErrNotFound
	}
	return s.GetMeasurement(ctx, id)
}

// DeleteMeasurement removes one measurement.
func (s *Store) DeleteMeasurement(ctx context.Context, id int64) error {
	res, err := s.db.ExecContext(ctx, `DELETE FROM measurements WHERE id = ?`, id)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return ErrNotFound
	}
	return nil
}

const measurementSelect = `
	SELECT m.id, m.device_id, d.name, d.address, d.kind, d.model,
	       m.type, m.unit, m.recorded_at, m.values_json, m.created_at
	FROM measurements m
	JOIN devices d ON d.id = m.device_id
`

type scanner interface {
	Scan(dest ...any) error
}

func scanDevice(row scanner) (Device, error) {
	var device Device
	var created, updated string
	if err := row.Scan(&device.ID, &device.Name, &device.Kind, &device.Address, &device.Model, &created, &updated); err != nil {
		return Device{}, err
	}
	var err error
	if device.CreatedAt, err = parseTime(created); err != nil {
		return Device{}, err
	}
	if device.UpdatedAt, err = parseTime(updated); err != nil {
		return Device{}, err
	}
	return device, nil
}

func scanMeasurement(row scanner) (Measurement, error) {
	var item Measurement
	var recorded, created, values string
	if err := row.Scan(
		&item.ID, &item.DeviceID, &item.DeviceName, &item.DeviceAddress, &item.DeviceKind, &item.DeviceModel,
		&item.Type, &item.Unit, &recorded, &values, &created,
	); err != nil {
		return Measurement{}, err
	}
	item.Values = json.RawMessage(values)
	var err error
	if item.RecordedAt, err = parseTime(recorded); err != nil {
		return Measurement{}, err
	}
	if item.CreatedAt, err = parseTime(created); err != nil {
		return Measurement{}, err
	}
	return item, nil
}

func formatTime(t time.Time) string {
	return t.UTC().Format(time.RFC3339Nano)
}

func parseTime(value string) (time.Time, error) {
	return time.Parse(time.RFC3339Nano, value)
}
