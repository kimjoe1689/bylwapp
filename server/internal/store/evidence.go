package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"time"

	"github.com/kimjoe1689/bylwapp/server/metrics"
)

type GroundTruth struct {
	ID             int64     `json:"id"`
	DeviceID       string    `json:"device_id"`
	MatchKey       string    `json:"match_key"`
	ReferenceType  string    `json:"reference_type"`
	ReferenceValue string    `json:"reference_value"`
	ObservedAt     time.Time `json:"observed_at"`
	Observer       string    `json:"observer"`
	Notes          string    `json:"notes"`
}

func (s *Store) AddGroundTruth(ctx context.Context, row GroundTruth) error {
	_, err := s.db.ExecContext(ctx, `
		INSERT INTO ground_truth(device_id, match_key, reference_type, reference_value, observed_at, observer, notes, created_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		row.DeviceID, row.MatchKey, row.ReferenceType, row.ReferenceValue,
		row.ObservedAt.UTC().Format(time.RFC3339), row.Observer, row.Notes, now())
	return err
}

func (s *Store) ListGroundTruth(ctx context.Context) ([]GroundTruth, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, device_id, match_key, reference_type, reference_value, observed_at, observer, notes
		FROM ground_truth ORDER BY id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []GroundTruth{}
	for rows.Next() {
		var row GroundTruth
		var observed string
		if err := rows.Scan(&row.ID, &row.DeviceID, &row.MatchKey, &row.ReferenceType, &row.ReferenceValue, &observed, &row.Observer, &row.Notes); err != nil {
			return nil, err
		}
		row.ObservedAt, _ = time.Parse(time.RFC3339, observed)
		out = append(out, row)
	}
	return out, rows.Err()
}

func (s *Store) Evidence(ctx context.Context) ([]metrics.EventView, []metrics.LedgerRow, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT device_id, measurement_type, monotonic_us, wall_time_utc, values_json FROM events`)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()
	events := []metrics.EventView{}
	for rows.Next() {
		var view metrics.EventView
		var values string
		var wall sql.NullString
		if err := rows.Scan(&view.DeviceID, &view.MeasurementType, &view.MonotonicUS, &wall, &values); err != nil {
			return nil, nil, err
		}
		if wall.Valid {
			if parsed, err := time.Parse(time.RFC3339, wall.String); err == nil {
				view.Wall = &parsed
			}
		}
		_ = json.Unmarshal([]byte(values), &view.Values)
		if view.Values == nil {
			view.Values = map[string]any{}
		}
		events = append(events, view)
	}
	if err := rows.Err(); err != nil {
		return nil, nil, err
	}
	ledgerRows, err := s.ListGroundTruth(ctx)
	if err != nil {
		return nil, nil, err
	}
	ledger := make([]metrics.LedgerRow, 0, len(ledgerRows))
	for _, row := range ledgerRows {
		ledger = append(ledger, metrics.LedgerRow{
			DeviceID: row.DeviceID, MatchKey: row.MatchKey,
			ReferenceType: row.ReferenceType, ReferenceValue: row.ReferenceValue,
		})
	}
	return events, ledger, nil
}
