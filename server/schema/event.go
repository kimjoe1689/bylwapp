// Package schema is the bylw-measure/1 creation contract.
//
// The phone app is the edge collector. Each BLE measurement becomes an
// immutable event. payload_hash is the SHA-256 of the canonical JSON and is
// not itself one of the hashed fields.
package schema

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"sort"
	"strconv"
	"strings"
	"time"
)

const SchemaVersion = "bylw-measure/1"

// Event is the device-created record. Sync lifecycle is not part of the hash.
type Event struct {
	SchemaVersion   string         `json:"schema_version"`
	EventID         string         `json:"event_id"`
	DeviceID        string         `json:"device_id"`
	SessionID       string         `json:"session_id"`
	SensorAddress   string         `json:"sensor_address"`
	SensorKind      string         `json:"sensor_kind"`
	SensorModel     string         `json:"sensor_model"`
	MeasurementType string         `json:"measurement_type"`
	Unit            string         `json:"unit"`
	MonotonicUS     int64          `json:"monotonic_us"`
	WallTimeUTC     *string        `json:"wall_time_utc"`
	ClockState      string         `json:"clock_state"`
	OperatingState  string         `json:"operating_state"`
	Values          map[string]any `json:"values"`
}

const (
	KindBloodPressure = "blood_pressure"
	KindHeartRate     = "heart_rate"
	KindRing          = "ring"
	KindCollector     = "collector"

	TypeBloodPressure  = "blood_pressure"
	TypeHeartRate      = "heart_rate"
	TypeSteps          = "steps"
	TypeSpO2           = "spo2"
	TypeSleep          = "sleep"
	TypeSleepSession   = "sleep_session"
	TypeStress         = "stress"
	TypeHRV            = "hrv"
	TypeTemperature    = "temperature"
	TypeOperatingState = "operating_state"
	TypeReminder       = "reminder"
	TypeCareAttention  = "care_attention"
	TypeWornState      = "worn_state"
	TypeDataGap        = "data_gap"
	TypeUsabilityTask  = "usability_task"
	TypeSUS            = "sus"
	TypeRawEvent       = "raw_event"
	TypeGesture        = "gesture"

	ClockUnset     = "UNSET"
	ClockNTPSynced = "NTP_SYNCED"
	ClockHoldover  = "HOLDOVER"
	ClockInvalid   = "INVALID"

	OpNominal = "NOMINAL"
	OpBLEDown = "BLE_DISCONNECTED"
	OpNetwork = "NETWORK_DEGRADED"
	OpAuth    = "AUTH_FAILURE"
	OpClock   = "CLOCK_DEGRADED"
)

// CanonicalJSON is the hash preimage: object keys sorted, values object keys
// sorted, whole numbers without a fraction, other numbers with 4 decimal places.
func CanonicalJSON(e Event) ([]byte, error) {
	if err := e.Validate(); err != nil {
		return nil, err
	}
	values, err := encodeValue(e.Values)
	if err != nil {
		return nil, err
	}
	parts := [][2]string{
		{"clock_state", jsonString(e.ClockState)},
		{"device_id", jsonString(e.DeviceID)},
		{"event_id", jsonString(e.EventID)},
		{"measurement_type", jsonString(e.MeasurementType)},
		{"monotonic_us", strconv.FormatInt(e.MonotonicUS, 10)},
		{"operating_state", jsonString(e.OperatingState)},
		{"schema_version", jsonString(e.SchemaVersion)},
		{"sensor_address", jsonString(e.SensorAddress)},
		{"sensor_kind", jsonString(e.SensorKind)},
		{"sensor_model", jsonString(e.SensorModel)},
		{"session_id", jsonString(e.SessionID)},
		{"unit", jsonString(e.Unit)},
		{"values", values},
		{"wall_time_utc", jsonStringPtr(e.WallTimeUTC)},
	}
	var b strings.Builder
	b.WriteByte('{')
	for i, part := range parts {
		if i > 0 {
			b.WriteByte(',')
		}
		b.WriteString(strconv.Quote(part[0]))
		b.WriteByte(':')
		b.WriteString(part[1])
	}
	b.WriteByte('}')
	return []byte(b.String()), nil
}

// PayloadHash is lowercase hex SHA-256 of CanonicalJSON.
func PayloadHash(e Event) (string, []byte, error) {
	body, err := CanonicalJSON(e)
	if err != nil {
		return "", nil, err
	}
	sum := sha256.Sum256(body)
	return hex.EncodeToString(sum[:]), body, nil
}

// NormalizeWallClock converts RFC3339 to UTC Zulu. Blank input is nil.
func NormalizeWallClock(raw *string) (*string, error) {
	if raw == nil || strings.TrimSpace(*raw) == "" {
		return nil, nil
	}
	parsed, err := time.Parse(time.RFC3339, strings.TrimSpace(*raw))
	if err != nil {
		return nil, fmt.Errorf("wall_time_utc: %w", err)
	}
	normalized := parsed.UTC().Format(time.RFC3339)
	return &normalized, nil
}

// Prepare normalizes the wall clock before validation and hashing.
func Prepare(e Event) (Event, error) {
	wall, err := NormalizeWallClock(e.WallTimeUTC)
	if err != nil {
		return Event{}, err
	}
	e.WallTimeUTC = wall
	if e.SchemaVersion == "" {
		e.SchemaVersion = SchemaVersion
	}
	if e.Values == nil {
		e.Values = map[string]any{}
	}
	return e, nil
}

// Validate checks a prepared event.
func (e Event) Validate() error {
	if e.SchemaVersion != SchemaVersion {
		return fmt.Errorf("schema_version must be %s", SchemaVersion)
	}
	if !token(e.EventID) || !token(e.DeviceID) || !token(e.SessionID) {
		return errors.New("event_id, device_id, and session_id must be path-safe tokens")
	}
	if !token(e.SensorAddress) || !token(e.SensorKind) {
		return errors.New("sensor_address and sensor_kind must be path-safe tokens")
	}
	if len(e.SensorModel) > 80 || len(e.Unit) > 16 || e.Unit == "" {
		return errors.New("unit is required and model/unit lengths are limited")
	}
	if e.MonotonicUS < 0 {
		return errors.New("monotonic_us must be >= 0")
	}
	if !oneOf(e.ClockState, ClockUnset, ClockNTPSynced, ClockHoldover, ClockInvalid) {
		return errors.New("clock_state is invalid")
	}
	if !oneOf(e.OperatingState, OpNominal, OpBLEDown, OpNetwork, OpAuth, OpClock) {
		return errors.New("operating_state is invalid")
	}
	if !oneOf(e.SensorKind, KindBloodPressure, KindHeartRate, KindRing, KindCollector) {
		return errors.New("sensor_kind is invalid")
	}
	if !oneOf(e.MeasurementType, TypeBloodPressure, TypeHeartRate, TypeSteps, TypeSpO2, TypeSleep, TypeSleepSession, TypeStress, TypeHRV, TypeTemperature, TypeOperatingState, TypeReminder, TypeCareAttention, TypeWornState, TypeDataGap, TypeUsabilityTask, TypeSUS, TypeRawEvent, TypeGesture) {
		return errors.New("measurement_type is invalid")
	}
	timed := e.ClockState == ClockNTPSynced || e.ClockState == ClockHoldover
	if timed && e.WallTimeUTC == nil {
		return errors.New("wall_time_utc is required when the clock is NTP_SYNCED or HOLDOVER")
	}
	if !timed && e.WallTimeUTC != nil {
		return errors.New("wall_time_utc must be null when the clock is UNSET or INVALID")
	}
	if e.WallTimeUTC != nil {
		if _, err := time.Parse(time.RFC3339, *e.WallTimeUTC); err != nil {
			return fmt.Errorf("wall_time_utc: %w", err)
		}
	}
	if e.Values == nil {
		return errors.New("values is required")
	}
	return nil
}

func token(value string) bool {
	if len(value) < 1 || len(value) > 128 {
		return false
	}
	for _, r := range value {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9', r == '.' || r == '_' || r == '-':
		default:
			return false
		}
	}
	return true
}

func oneOf(value string, allowed ...string) bool {
	for _, item := range allowed {
		if value == item {
			return true
		}
	}
	return false
}

func encodeValue(value any) (string, error) {
	switch typed := value.(type) {
	case nil:
		return "null", nil
	case string:
		return jsonString(typed), nil
	case bool:
		if typed {
			return "true", nil
		}
		return "false", nil
	case int:
		return strconv.Itoa(typed), nil
	case int64:
		return strconv.FormatInt(typed, 10), nil
	case float64:
		if math.IsNaN(typed) || math.IsInf(typed, 0) {
			return "", errors.New("values cannot contain NaN or infinity")
		}
		if typed == math.Trunc(typed) && math.Abs(typed) < 1e15 {
			return strconv.FormatInt(int64(typed), 10), nil
		}
		return strconv.FormatFloat(typed, 'f', 4, 64), nil
	case json.Number:
		parsed, err := typed.Float64()
		if err != nil {
			return "", err
		}
		return encodeValue(parsed)
	case map[string]any:
		keys := make([]string, 0, len(typed))
		for key := range typed {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		var b strings.Builder
		b.WriteByte('{')
		for i, key := range keys {
			raw, err := encodeValue(typed[key])
			if err != nil {
				return "", err
			}
			if i > 0 {
				b.WriteByte(',')
			}
			b.WriteString(strconv.Quote(key))
			b.WriteByte(':')
			b.WriteString(raw)
		}
		b.WriteByte('}')
		return b.String(), nil
	case []any:
		var b strings.Builder
		b.WriteByte('[')
		for i, item := range typed {
			raw, err := encodeValue(item)
			if err != nil {
				return "", err
			}
			if i > 0 {
				b.WriteByte(',')
			}
			b.WriteString(raw)
		}
		b.WriteByte(']')
		return b.String(), nil
	default:
		return "", fmt.Errorf("unsupported value type %T", value)
	}
}

func jsonString(value string) string {
	body, _ := json.Marshal(value)
	return string(body)
}

func jsonStringPtr(value *string) string {
	if value == nil {
		return "null"
	}
	return jsonString(*value)
}
