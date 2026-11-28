// Package devicesim rehearses collector sync faults. It is not a source of thesis results.
package devicesim

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/kimjoe1689/bylwapp/server/schema"
)

const (
	StatePending     = "pending"
	StateSynced      = "synced"
	StateConflict    = "conflict"
	StateAuthBlocked = "auth_blocked"
	StateRetryFailed = "retry_failed"
)

// Record is one locally confirmed event waiting on the sync worker.
type Record struct {
	Event     schema.Event
	Hash      string
	Canonical string
	State     string
	Attempts  int
	LastError string
}

// Journal is the simulator's stand-in for the phone SQLite journal.
type Journal struct {
	Records []*Record
}

func (j *Journal) Add(event schema.Event) (*Record, error) {
	prepared, err := schema.Prepare(event)
	if err != nil {
		return nil, err
	}
	hash, body, err := schema.PayloadHash(prepared)
	if err != nil {
		return nil, err
	}
	record := &Record{Event: prepared, Hash: hash, Canonical: string(body), State: StatePending}
	j.Records = append(j.Records, record)
	return record, nil
}

func (j *Journal) Pending() []*Record {
	out := []*Record{}
	for _, record := range j.Records {
		if record.State == StatePending || record.State == StateRetryFailed {
			out = append(out, record)
		}
	}
	return out
}

// Gateway is the server the sync worker can see.
type Gateway interface {
	Post(ctx context.Context, record *Record) (result string, err error)
	Read(ctx context.Context, deviceID, eventID string) (hash string, found bool, err error)
}

// HTTPGateway talks to the Go server the way the phone app does.
type HTTPGateway struct {
	BaseURL     string
	Token       string
	Client      *http.Client
	DropReply   bool
	NetworkDown bool
}

func (g HTTPGateway) Post(ctx context.Context, record *Record) (string, error) {
	if g.NetworkDown {
		return "", errors.New("network down")
	}
	payload, _ := json.Marshal(map[string]any{"event": json.RawMessage(record.Canonical), "payload_hash": record.Hash})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, g.BaseURL+"/api/v1/devices/"+record.Event.DeviceID+"/events", bytes.NewReader(payload))
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "Bearer "+g.Token)
	req.Header.Set("Content-Type", "application/json")
	res, err := g.client().Do(req)
	if err != nil {
		return "", err
	}
	defer res.Body.Close()
	if g.DropReply {
		return "", errors.New("timeout after commit")
	}
	defer res.Body.Close()
	body, _ := io.ReadAll(res.Body)
	var parsed struct {
		Result string `json:"result"`
	}
	_ = json.Unmarshal(body, &parsed)
	if res.StatusCode == http.StatusUnauthorized {
		return "auth_blocked", nil
	}
	if res.StatusCode != http.StatusCreated && res.StatusCode != http.StatusOK && res.StatusCode != http.StatusConflict {
		return "", fmt.Errorf("ingest %d %s", res.StatusCode, body)
	}
	return parsed.Result, nil
}

func (g HTTPGateway) Read(ctx context.Context, deviceID, eventID string) (string, bool, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, g.BaseURL+"/api/v1/devices/"+deviceID+"/events/"+eventID, nil)
	if err != nil {
		return "", false, err
	}
	req.Header.Set("Authorization", "Bearer "+g.Token)
	res, err := g.client().Do(req)
	if err != nil {
		return "", false, err
	}
	defer res.Body.Close()
	if res.StatusCode == http.StatusNotFound {
		return "", false, nil
	}
	body, _ := io.ReadAll(res.Body)
	if res.StatusCode != http.StatusOK {
		return "", false, fmt.Errorf("readback %d %s", res.StatusCode, body)
	}
	var parsed struct {
		PayloadHash string `json:"payload_hash"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil {
		return "", false, err
	}
	return parsed.PayloadHash, true, nil
}

func (g HTTPGateway) client() *http.Client {
	if g.Client != nil {
		return g.Client
	}
	return http.DefaultClient
}

// SyncOnce uploads pending records. A timeout after the server may have committed
// is reconciled by reading the same event_id back.
func SyncOnce(ctx context.Context, journal *Journal, gateway Gateway) error {
	for _, record := range journal.Pending() {
		record.Attempts++
		result, err := gateway.Post(ctx, record)
		if err != nil {
			hash, found, readErr := gateway.Read(ctx, record.Event.DeviceID, record.Event.EventID)
			if readErr == nil && found {
				if hash == record.Hash {
					record.State = StateSynced
					record.LastError = ""
					continue
				}
				record.State = StateConflict
				record.LastError = "read-back hash differs"
				continue
			}
			record.LastError = err.Error()
			if record.Attempts >= 3 {
				record.State = StateRetryFailed
			}
			continue
		}
		switch result {
		case "stored", "duplicate":
			record.State = StateSynced
			record.LastError = ""
		case "conflict":
			record.State = StateConflict
			record.LastError = "server kept the first receipt"
		case "auth_blocked":
			record.State = StateAuthBlocked
			record.LastError = "device token rejected"
		default:
			record.LastError = result
		}
	}
	return nil
}

// SampleBloodPressure builds one canonical measurement. skew shifts the wall clock.
func SampleBloodPressure(deviceID, eventID string, skew time.Duration) (schema.Event, error) {
	wall := time.Date(2026, 11, 27, 8, 15, 9, 0, time.UTC).Add(skew).Format(time.RFC3339)
	clock := schema.ClockNTPSynced
	operating := schema.OpNominal
	if skew != 0 {
		clock = schema.ClockHoldover
		operating = schema.OpClock
	}
	return schema.Prepare(schema.Event{
		EventID: eventID, DeviceID: deviceID, SessionID: "sess-sim",
		SensorAddress: "AA-BB-CC-DD-EE-01", SensorKind: schema.KindBloodPressure, SensorModel: "Yuwell YE680B",
		MeasurementType: schema.TypeBloodPressure, Unit: "mmHg", MonotonicUS: 1000,
		WallTimeUTC: &wall, ClockState: clock, OperatingState: operating,
		Values: map[string]any{"systolic": 128.0, "diastolic": 82.0, "pulse": 70.0},
	})
}
