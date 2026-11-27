package store

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"time"

	"github.com/kimjoe1689/bylwapp/server/schema"
	"golang.org/x/crypto/bcrypt"
	_ "modernc.org/sqlite"
)

var ErrNotFound = errors.New("not found")
var ErrConflict = errors.New("conflict")

type Store struct{ db *sql.DB }

type User struct {
	ID       int64  `json:"id"`
	Username string `json:"username"`
	Role     string `json:"role"`
}

type Device struct {
	DeviceID  string    `json:"device_id"`
	Name      string    `json:"name"`
	CreatedAt time.Time `json:"created_at"`
}

type StoredEvent struct {
	Event            schema.Event `json:"event"`
	PayloadHash      string       `json:"payload_hash"`
	CanonicalJSON    string       `json:"canonical_json"`
	ServerReceivedAt time.Time    `json:"server_received_at"`
}

type IngestOutcome struct {
	Result           string    `json:"result"`
	PayloadHash      string    `json:"payload_hash"`
	ServerReceivedAt time.Time `json:"server_received_at"`
}

type DeviceStatus struct {
	DeviceID       string     `json:"device_id"`
	Name           string     `json:"name"`
	LastReceivedAt *time.Time `json:"last_received_at"`
	Stale          bool       `json:"stale"`
	OperatingState string     `json:"operating_state"`
	SensorAddress  string     `json:"sensor_address"`
	SensorKind     string     `json:"sensor_kind"`
	SensorModel    string     `json:"sensor_model"`
	OpenConflicts  int        `json:"open_conflicts"`
	DuplicateAcks  int        `json:"duplicate_acks"`
	EventCount     int        `json:"event_count"`
}

type ConflictRow struct {
	DeviceID      string    `json:"device_id"`
	EventID       string    `json:"event_id"`
	StoredHash    string    `json:"stored_hash"`
	PresentedHash string    `json:"presented_hash"`
	At            time.Time `json:"at"`
}

type SeriesPoint struct {
	At    time.Time `json:"at"`
	Value float64   `json:"value"`
	Label string    `json:"label"`
}

func Open(path string) (*Store, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, err
	}
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	var mode string
	if err := db.QueryRow(`PRAGMA journal_mode = WAL`).Scan(&mode); err != nil {
		_ = db.Close()
		return nil, err
	}
	if _, err := db.Exec(`PRAGMA foreign_keys = ON`); err != nil {
		_ = db.Close()
		return nil, err
	}
	if _, err := db.Exec(`PRAGMA busy_timeout = 5000`); err != nil {
		_ = db.Close()
		return nil, err
	}
	return &Store{db: db}, db.Ping()
}

func (s *Store) Close() error                   { return s.db.Close() }
func (s *Store) DB() *sql.DB                    { return s.db }
func (s *Store) Ping(ctx context.Context) error { return s.db.PingContext(ctx) }

func (s *Store) CountUsers(ctx context.Context) (int, error) {
	var n int
	err := s.db.QueryRowContext(ctx, `SELECT COUNT(1) FROM users`).Scan(&n)
	return n, err
}

func (s *Store) CreateUser(ctx context.Context, username, password, role string, cost int) error {
	if role != "admin" && role != "caregiver" {
		return errors.New("invalid role")
	}
	if cost == 0 {
		cost = bcrypt.DefaultCost
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(password), cost)
	if err != nil {
		return err
	}
	_, err = s.db.ExecContext(ctx, `INSERT INTO users(username, password_hash, role, created_at) VALUES (?, ?, ?, ?)`,
		username, string(hash), role, now())
	return err
}

func (s *Store) Login(ctx context.Context, username, password string, ttl time.Duration) (string, User, error) {
	var user User
	var hash string
	err := s.db.QueryRowContext(ctx, `SELECT id, username, role, password_hash FROM users WHERE username = ?`, username).
		Scan(&user.ID, &user.Username, &user.Role, &hash)
	if errors.Is(err, sql.ErrNoRows) {
		return "", User{}, ErrNotFound
	}
	if err != nil {
		return "", User{}, err
	}
	if bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) != nil {
		return "", User{}, ErrNotFound
	}
	token, tokenHash, err := newToken()
	if err != nil {
		return "", User{}, err
	}
	_, err = s.db.ExecContext(ctx, `INSERT INTO sessions(token_hash, user_id, expires_at) VALUES (?, ?, ?)`,
		tokenHash, user.ID, time.Now().UTC().Add(ttl).Format(time.RFC3339Nano))
	return token, user, err
}

func (s *Store) UserByToken(ctx context.Context, token string) (User, error) {
	var user User
	var expires string
	err := s.db.QueryRowContext(ctx, `
		SELECT u.id, u.username, u.role, s.expires_at
		FROM sessions s JOIN users u ON u.id = s.user_id
		WHERE s.token_hash = ?`, hashToken(token)).Scan(&user.ID, &user.Username, &user.Role, &expires)
	if errors.Is(err, sql.ErrNoRows) {
		return User{}, ErrNotFound
	}
	if err != nil {
		return User{}, err
	}
	exp, err := time.Parse(time.RFC3339Nano, expires)
	if err != nil || time.Now().After(exp) {
		return User{}, ErrNotFound
	}
	return user, nil
}

func (s *Store) UpsertDevice(ctx context.Context, id, name string) error {
	_, err := s.db.ExecContext(ctx, `
		INSERT INTO devices(device_id, name, created_at) VALUES (?, ?, ?)
		ON CONFLICT(device_id) DO UPDATE SET name = excluded.name`, id, name, now())
	return err
}

func (s *Store) IssueDeviceToken(ctx context.Context, deviceID string) (string, error) {
	var n int
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(1) FROM devices WHERE device_id = ?`, deviceID).Scan(&n); err != nil {
		return "", err
	}
	if n == 0 {
		return "", ErrNotFound
	}
	token, tokenHash, err := newToken()
	if err != nil {
		return "", err
	}
	_, err = s.db.ExecContext(ctx, `INSERT INTO device_tokens(token_hash, device_id, created_at) VALUES (?, ?, ?)`,
		tokenHash, deviceID, now())
	return token, err
}

func (s *Store) DeviceByToken(ctx context.Context, token string) (string, error) {
	var deviceID string
	var revoked sql.NullString
	err := s.db.QueryRowContext(ctx, `SELECT device_id, revoked_at FROM device_tokens WHERE token_hash = ?`, hashToken(token)).
		Scan(&deviceID, &revoked)
	if errors.Is(err, sql.ErrNoRows) || revoked.Valid {
		return "", ErrNotFound
	}
	return deviceID, err
}

func (s *Store) ListDevices(ctx context.Context) ([]Device, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT device_id, name, created_at FROM devices ORDER BY device_id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Device{}
	for rows.Next() {
		var d Device
		var created string
		if err := rows.Scan(&d.DeviceID, &d.Name, &created); err != nil {
			return nil, err
		}
		d.CreatedAt, _ = time.Parse(time.RFC3339Nano, created)
		out = append(out, d)
	}
	return out, rows.Err()
}

// Ingest inserts the first receipt or records a duplicate/conflict without replacing it.
func (s *Store) Ingest(ctx context.Context, event schema.Event, hash, canonical string) (IngestOutcome, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return IngestOutcome{}, err
	}
	defer func() { _ = tx.Rollback() }()
	var storedHash, received string
	err = tx.QueryRowContext(ctx, `SELECT payload_hash, server_received_at FROM events WHERE device_id = ? AND event_id = ?`,
		event.DeviceID, event.EventID).Scan(&storedHash, &received)
	if errors.Is(err, sql.ErrNoRows) {
		received = now()
		_, err = tx.ExecContext(ctx, `
			INSERT INTO events(device_id, event_id, payload_hash, canonical_json, server_received_at,
				measurement_type, unit, sensor_address, sensor_kind, sensor_model, monotonic_us,
				wall_time_utc, clock_state, operating_state, values_json)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			event.DeviceID, event.EventID, hash, canonical, received,
			event.MeasurementType, event.Unit, event.SensorAddress, event.SensorKind, event.SensorModel,
			event.MonotonicUS, nullable(event.WallTimeUTC), event.ClockState, event.OperatingState, mustValues(event.Values))
		if err != nil {
			return IngestOutcome{}, err
		}
		if err := logIngest(ctx, tx, event.DeviceID, event.EventID, "stored", hash, hash, received); err != nil {
			return IngestOutcome{}, err
		}
		if err := tx.Commit(); err != nil {
			return IngestOutcome{}, err
		}
		at, _ := time.Parse(time.RFC3339Nano, received)
		return IngestOutcome{Result: "stored", PayloadHash: hash, ServerReceivedAt: at}, nil
	}
	if err != nil {
		return IngestOutcome{}, err
	}
	result := "duplicate"
	if storedHash != hash {
		result = "conflict"
	}
	at := now()
	if err := logIngest(ctx, tx, event.DeviceID, event.EventID, result, hash, storedHash, at); err != nil {
		return IngestOutcome{}, err
	}
	if err := tx.Commit(); err != nil {
		return IngestOutcome{}, err
	}
	parsed, _ := time.Parse(time.RFC3339Nano, received)
	return IngestOutcome{Result: result, PayloadHash: storedHash, ServerReceivedAt: parsed}, nil
}

func (s *Store) GetEvent(ctx context.Context, deviceID, eventID string) (StoredEvent, error) {
	row := s.db.QueryRowContext(ctx, `SELECT canonical_json, payload_hash, server_received_at FROM events WHERE device_id = ? AND event_id = ?`, deviceID, eventID)
	var body, hash, received string
	if err := row.Scan(&body, &hash, &received); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return StoredEvent{}, ErrNotFound
		}
		return StoredEvent{}, err
	}
	var event schema.Event
	if err := json.Unmarshal([]byte(body), &event); err != nil {
		return StoredEvent{}, err
	}
	at, _ := time.Parse(time.RFC3339Nano, received)
	return StoredEvent{Event: event, PayloadHash: hash, CanonicalJSON: body, ServerReceivedAt: at}, nil
}

func (s *Store) ListEvents(ctx context.Context, limit int) ([]StoredEvent, error) {
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	rows, err := s.db.QueryContext(ctx, `
		SELECT canonical_json, payload_hash, server_received_at
		FROM events ORDER BY server_received_at DESC, event_id DESC LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanEvents(rows)
}

func (s *Store) ListAllEvents(ctx context.Context) ([]StoredEvent, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT canonical_json, payload_hash, server_received_at
		FROM events ORDER BY server_received_at ASC, event_id ASC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanEvents(rows)
}

func (s *Store) DeviceStatuses(ctx context.Context, staleAfter time.Duration) ([]DeviceStatus, error) {
	devices, err := s.ListDevices(ctx)
	if err != nil {
		return nil, err
	}
	out := make([]DeviceStatus, 0, len(devices))
	for _, device := range devices {
		status := DeviceStatus{DeviceID: device.DeviceID, Name: device.Name, OperatingState: ""}
		var received, operating, address, kind, model sql.NullString
		err := s.db.QueryRowContext(ctx, `
			SELECT server_received_at, operating_state, sensor_address, sensor_kind, sensor_model
			FROM events WHERE device_id = ? ORDER BY server_received_at DESC LIMIT 1`, device.DeviceID).
			Scan(&received, &operating, &address, &kind, &model)
		if err == nil {
			at, _ := time.Parse(time.RFC3339Nano, received.String)
			status.LastReceivedAt = &at
			status.Stale = time.Since(at) > staleAfter
			status.OperatingState = operating.String
			status.SensorAddress = address.String
			status.SensorKind = kind.String
			status.SensorModel = model.String
		} else if !errors.Is(err, sql.ErrNoRows) {
			return nil, err
		} else {
			status.Stale = true
		}
		if err := s.db.QueryRowContext(ctx, `SELECT COUNT(1) FROM events WHERE device_id = ?`, device.DeviceID).Scan(&status.EventCount); err != nil {
			return nil, err
		}
		if err := s.db.QueryRowContext(ctx, `SELECT COUNT(1) FROM ingest_log WHERE device_id = ? AND result = 'conflict'`, device.DeviceID).Scan(&status.OpenConflicts); err != nil {
			return nil, err
		}
		if err := s.db.QueryRowContext(ctx, `SELECT COUNT(1) FROM ingest_log WHERE device_id = ? AND result = 'duplicate'`, device.DeviceID).Scan(&status.DuplicateAcks); err != nil {
			return nil, err
		}
		out = append(out, status)
	}
	return out, nil
}

func (s *Store) Conflicts(ctx context.Context, limit int) ([]ConflictRow, error) {
	if limit <= 0 {
		limit = 100
	}
	rows, err := s.db.QueryContext(ctx, `
		SELECT device_id, event_id, stored_hash, presented_hash, at
		FROM ingest_log WHERE result = 'conflict' ORDER BY id DESC LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []ConflictRow{}
	for rows.Next() {
		var row ConflictRow
		var at string
		if err := rows.Scan(&row.DeviceID, &row.EventID, &row.StoredHash, &row.PresentedHash, &at); err != nil {
			return nil, err
		}
		row.At, _ = time.Parse(time.RFC3339Nano, at)
		out = append(out, row)
	}
	return out, rows.Err()
}

func (s *Store) Series(ctx context.Context, deviceID, measurementType string, limit int) ([]SeriesPoint, error) {
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	query := `
		SELECT server_received_at, values_json, measurement_type
		FROM events WHERE measurement_type = ?`
	args := []any{measurementType}
	if deviceID != "" {
		query += ` AND device_id = ?`
		args = append(args, deviceID)
	}
	query += ` ORDER BY server_received_at DESC LIMIT ?`
	args = append(args, limit)
	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []SeriesPoint{}
	for rows.Next() {
		var at, values string
		var kind string
		if err := rows.Scan(&at, &values, &kind); err != nil {
			return nil, err
		}
		parsed, _ := time.Parse(time.RFC3339Nano, at)
		var payload map[string]any
		_ = json.Unmarshal([]byte(values), &payload)
		value, label := seriesValue(kind, payload)
		out = append(out, SeriesPoint{At: parsed, Value: value, Label: label})
	}
	return out, rows.Err()
}

func (s *Store) Counts(ctx context.Context) (stored, duplicates, conflicts int, err error) {
	if err = s.db.QueryRowContext(ctx, `SELECT COUNT(1) FROM events`).Scan(&stored); err != nil {
		return
	}
	if err = s.db.QueryRowContext(ctx, `SELECT COUNT(1) FROM ingest_log WHERE result = 'duplicate'`).Scan(&duplicates); err != nil {
		return
	}
	err = s.db.QueryRowContext(ctx, `SELECT COUNT(1) FROM ingest_log WHERE result = 'conflict'`).Scan(&conflicts)
	return
}

func seriesValue(kind string, values map[string]any) (float64, string) {
	switch kind {
	case schema.TypeBloodPressure:
		return asFloat(values["systolic"]), "systolic"
	case schema.TypeHeartRate:
		return asFloat(values["bpm"]), "bpm"
	case schema.TypeSpO2:
		return asFloat(values["spo2"]), "spo2"
	case schema.TypeTemperature:
		return asFloat(values["celsius"]), "celsius"
	case schema.TypeSteps:
		return asFloat(values["steps"]), "steps"
	case schema.TypeStress:
		return asFloat(values["stress"]), "stress"
	case schema.TypeHRV:
		return asFloat(values["hrv_ms"]), "hrv_ms"
	default:
		return 0, ""
	}
}

func asFloat(value any) float64 {
	switch typed := value.(type) {
	case float64:
		return typed
	case int:
		return float64(typed)
	case int64:
		return float64(typed)
	default:
		return 0
	}
}

func scanEvents(rows *sql.Rows) ([]StoredEvent, error) {
	out := []StoredEvent{}
	for rows.Next() {
		var body, hash, received string
		if err := rows.Scan(&body, &hash, &received); err != nil {
			return nil, err
		}
		var event schema.Event
		if err := json.Unmarshal([]byte(body), &event); err != nil {
			return nil, err
		}
		at, _ := time.Parse(time.RFC3339Nano, received)
		out = append(out, StoredEvent{Event: event, PayloadHash: hash, CanonicalJSON: body, ServerReceivedAt: at})
	}
	return out, rows.Err()
}

func logIngest(ctx context.Context, tx *sql.Tx, deviceID, eventID, result, presented, stored, at string) error {
	_, err := tx.ExecContext(ctx, `
		INSERT INTO ingest_log(device_id, event_id, result, presented_hash, stored_hash, at)
		VALUES (?, ?, ?, ?, ?, ?)`, deviceID, eventID, result, presented, stored, at)
	return err
}

func mustValues(values map[string]any) string {
	body, _ := json.Marshal(values)
	return string(body)
}

func nullable(value *string) any {
	if value == nil {
		return nil
	}
	return *value
}

func now() string { return time.Now().UTC().Format(time.RFC3339Nano) }

func newToken() (string, string, error) {
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		return "", "", err
	}
	token := hex.EncodeToString(buf)
	return token, hashToken(token), nil
}

func hashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}
