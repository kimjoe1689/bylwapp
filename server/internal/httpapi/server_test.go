package httpapi

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"

	"github.com/kimjoe1689/bylwapp/server/internal/migrate"
	"github.com/kimjoe1689/bylwapp/server/internal/store"
	"github.com/kimjoe1689/bylwapp/server/schema"
	"golang.org/x/crypto/bcrypt"
)

func TestIngestIdempotencyReadBackAndRoles(t *testing.T) {
	srv, st := testServer(t)
	admin := login(t, srv, "admin", "admin-pass-1")
	care := createAndLogin(t, srv, admin, "care", "care-pass-1", "caregiver")
	deviceToken := createDevice(t, srv, admin, "phone-1", "采集手机")

	event := sampleEvent("evt-0001")
	hash, _, err := schema.PayloadHash(event)
	if err != nil {
		t.Fatal(err)
	}
	first := do(t, srv, http.MethodPost, "/api/v1/devices/phone-1/events", eventBody(event, hash), deviceToken)
	if first.Code != http.StatusCreated {
		t.Fatalf("store %d %s", first.Code, first.Body.String())
	}
	dup := do(t, srv, http.MethodPost, "/api/v1/devices/phone-1/events", eventBody(event, hash), deviceToken)
	if dup.Code != http.StatusOK || !bytes.Contains(dup.Body.Bytes(), []byte(`"duplicate"`)) {
		t.Fatalf("duplicate %d %s", dup.Code, dup.Body.String())
	}
	changed := event
	changed.MonotonicUS = 9999
	changedHash, _, err := schema.PayloadHash(changed)
	if err != nil {
		t.Fatal(err)
	}
	conflict := do(t, srv, http.MethodPost, "/api/v1/devices/phone-1/events", eventBody(changed, changedHash), deviceToken)
	if conflict.Code != http.StatusConflict {
		t.Fatalf("conflict %d %s", conflict.Code, conflict.Body.String())
	}
	read := do(t, srv, http.MethodGet, "/api/v1/devices/phone-1/events/evt-0001", nil, deviceToken)
	if read.Code != http.StatusOK || !bytes.Contains(read.Body.Bytes(), []byte(hash)) {
		t.Fatalf("readback kept the first hash? %d %s", read.Code, read.Body.String())
	}
	if bytes.Contains(read.Body.Bytes(), []byte(changedHash)) {
		t.Fatal("conflict overwrote the first receipt")
	}

	denied := do(t, srv, http.MethodGet, "/api/v1/dashboard/events", nil, deviceToken)
	if denied.Code != http.StatusUnauthorized {
		t.Fatalf("device dashboard %d", denied.Code)
	}
	forbidden := do(t, srv, http.MethodPost, "/api/v1/admin/devices", map[string]string{"device_id": "x", "name": "x"}, care)
	if forbidden.Code != http.StatusForbidden {
		t.Fatalf("caregiver admin %d %s", forbidden.Code, forbidden.Body.String())
	}
	list := do(t, srv, http.MethodGet, "/api/v1/dashboard/events", nil, care)
	if list.Code != http.StatusOK || !bytes.Contains(list.Body.Bytes(), []byte("evt-0001")) {
		t.Fatalf("dashboard %d %s", list.Code, list.Body.String())
	}
	series := do(t, srv, http.MethodGet, "/api/v1/dashboard/series?type=blood_pressure", nil, care)
	if series.Code != http.StatusOK || !bytes.Contains(series.Body.Bytes(), []byte("systolic")) {
		t.Fatalf("series %d %s", series.Code, series.Body.String())
	}
	recon := do(t, srv, http.MethodGet, "/api/v1/exports/reconciliation.json", nil, admin)
	if recon.Code != http.StatusOK || !bytes.Contains(recon.Body.Bytes(), []byte(`"conflicts": 1`)) && !bytes.Contains(recon.Body.Bytes(), []byte(`"conflicts":1`)) {
		t.Fatalf("reconciliation %s", recon.Body.String())
	}
	page := do(t, srv, http.MethodGet, "/", nil, "")
	if page.Code != http.StatusOK || !bytes.Contains(page.Body.Bytes(), []byte("管理后台")) {
		t.Fatalf("page %d", page.Code)
	}
	_ = st
}

func testServer(t *testing.T) (http.Handler, *store.Store) {
	t.Helper()
	st, err := store.Open(filepath.Join(t.TempDir(), "api.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = st.Close() })
	if err := migrate.Up(st.DB()); err != nil {
		t.Fatal(err)
	}
	if err := st.CreateUser(t.Context(), "admin", "admin-pass-1", "admin", bcrypt.MinCost); err != nil {
		t.Fatal(err)
	}
	return New(st, time.Minute), st
}

func login(t *testing.T, h http.Handler, user, pass string) string {
	t.Helper()
	res := do(t, h, http.MethodPost, "/api/v1/auth/login", map[string]string{"username": user, "password": pass}, "")
	if res.Code != http.StatusOK {
		t.Fatalf("login %d %s", res.Code, res.Body.String())
	}
	var body map[string]string
	decodeBody(t, res, &body)
	return body["token"]
}

func createAndLogin(t *testing.T, h http.Handler, admin, user, pass, role string) string {
	t.Helper()
	res := do(t, h, http.MethodPost, "/api/v1/admin/users", map[string]string{"username": user, "password": pass, "role": role}, admin)
	if res.Code != http.StatusCreated {
		t.Fatalf("create user %d %s", res.Code, res.Body.String())
	}
	return login(t, h, user, pass)
}

func createDevice(t *testing.T, h http.Handler, admin, id, name string) string {
	t.Helper()
	res := do(t, h, http.MethodPost, "/api/v1/admin/devices", map[string]string{"device_id": id, "name": name}, admin)
	if res.Code != http.StatusCreated {
		t.Fatalf("device %d %s", res.Code, res.Body.String())
	}
	res = do(t, h, http.MethodPost, "/api/v1/admin/devices/"+id+"/tokens", map[string]string{}, admin)
	if res.Code != http.StatusCreated {
		t.Fatalf("token %d %s", res.Code, res.Body.String())
	}
	var body map[string]string
	decodeBody(t, res, &body)
	return body["token"]
}

func sampleEvent(id string) schema.Event {
	wall := "2026-11-27T08:15:09Z"
	event, err := schema.Prepare(schema.Event{
		EventID: id, DeviceID: "phone-1", SessionID: "sess-1",
		SensorAddress: "AA-BB-CC-DD-EE-01", SensorKind: schema.KindBloodPressure, SensorModel: "Yuwell YE680B",
		MeasurementType: schema.TypeBloodPressure, Unit: "mmHg", MonotonicUS: 1000,
		WallTimeUTC: &wall, ClockState: schema.ClockNTPSynced, OperatingState: schema.OpNominal,
		Values: map[string]any{"systolic": 120.0, "diastolic": 80.0, "pulse": 72.0},
	})
	if err != nil {
		panic(err)
	}
	return event
}

func eventBody(event schema.Event, hash string) map[string]any {
	return map[string]any{"event": event, "payload_hash": hash}
}

func do(t *testing.T, h http.Handler, method, path string, body any, token string) *httptest.ResponseRecorder {
	t.Helper()
	var buf bytes.Buffer
	if body != nil {
		if err := json.NewEncoder(&buf).Encode(body); err != nil {
			t.Fatal(err)
		}
	}
	req := httptest.NewRequest(method, path, &buf)
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	res := httptest.NewRecorder()
	h.ServeHTTP(res, req)
	return res
}

func decodeBody(t *testing.T, res *httptest.ResponseRecorder, dest any) {
	t.Helper()
	if err := json.Unmarshal(res.Body.Bytes(), dest); err != nil {
		t.Fatalf("decode %s: %v", res.Body.String(), err)
	}
}
