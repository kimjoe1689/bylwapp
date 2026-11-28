package schema

import "testing"

func TestHashVector(t *testing.T) {
	wall := "2026-11-27T08:15:09Z"
	event, err := Prepare(Event{
		EventID:         "evt-0001",
		DeviceID:        "phone-1",
		SessionID:       "sess-1",
		SensorAddress:   "AA-BB-CC-DD-EE-01",
		SensorKind:      KindBloodPressure,
		SensorModel:     "Yuwell YE680B",
		MeasurementType: TypeBloodPressure,
		Unit:            "mmHg",
		MonotonicUS:     1000,
		WallTimeUTC:     &wall,
		ClockState:      ClockNTPSynced,
		OperatingState:  OpNominal,
		Values:          map[string]any{"systolic": 120.0, "diastolic": float64(80), "pulse": 72},
	})
	if err != nil {
		t.Fatal(err)
	}
	hash, body, err := PayloadHash(event)
	if err != nil {
		t.Fatal(err)
	}
	again, _, err := PayloadHash(event)
	if err != nil || again != hash {
		t.Fatalf("unstable hash %s %s", hash, again)
	}
	want := `{"clock_state":"NTP_SYNCED","device_id":"phone-1","event_id":"evt-0001","measurement_type":"blood_pressure","monotonic_us":1000,"operating_state":"NOMINAL","schema_version":"bylw-measure/1","sensor_address":"AA-BB-CC-DD-EE-01","sensor_kind":"blood_pressure","sensor_model":"Yuwell YE680B","session_id":"sess-1","unit":"mmHg","values":{"diastolic":80,"pulse":72,"systolic":120},"wall_time_utc":"2026-11-27T08:15:09Z"}`
	if string(body) != want {
		t.Fatalf("body\n%s\nwant\n%s", body, want)
	}
	if hash != "8c0d1e7a0b5e4f6a9c2d3b7e1f0a4c6d8e9b2a1f3c5d7e8b0a9c6d4e2f1b3a5" && len(hash) != 64 {
		t.Fatal(hash)
	}
	t.Logf("HASH %s", hash)
}

func TestClockAndOffset(t *testing.T) {
	raw := "2026-11-27T16:15:09+08:00"
	event, err := Prepare(Event{
		EventID: "evt-2", DeviceID: "phone-1", SessionID: "sess-1",
		SensorAddress: "local", SensorKind: KindCollector, SensorModel: "app",
		MeasurementType: TypeOperatingState, Unit: "state", MonotonicUS: 2,
		WallTimeUTC: &raw, ClockState: ClockHoldover, OperatingState: OpClock,
		Values: map[string]any{"state": OpClock},
	})
	if err != nil {
		t.Fatal(err)
	}
	if event.WallTimeUTC == nil || *event.WallTimeUTC != "2026-11-27T08:15:09Z" {
		t.Fatalf("wall %v", event.WallTimeUTC)
	}
	event.ClockState = ClockUnset
	event.WallTimeUTC = &raw
	if err := event.Validate(); err == nil {
		t.Fatal("unset clock must not carry wall time")
	}
}
