package httpapi

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strconv"
	"testing"

	"github.com/kimjoe1689/bylwapp/server/internal/migrate"
	"github.com/kimjoe1689/bylwapp/server/internal/store"
)

func TestHealthAndAdminPage(t *testing.T) {
	srv := testServer(t)
	res := do(t, srv, http.MethodGet, "/health", nil)
	if res.Code != http.StatusOK {
		t.Fatalf("health status %d", res.Code)
	}
	var body map[string]string
	decode(t, res, &body)
	if body["status"] != "ok" {
		t.Fatalf("health body %#v", body)
	}

	page := do(t, srv, http.MethodGet, "/", nil)
	if page.Code != http.StatusOK || !bytes.Contains(page.Body.Bytes(), []byte("管理后台")) {
		t.Fatalf("admin page status %d body %s", page.Code, page.Body.String())
	}
}

func TestSyncCRUDAndIdempotency(t *testing.T) {
	srv := testServer(t)
	payload := map[string]any{
		"device": map[string]string{
			"name":    "YE680B",
			"kind":    "blood_pressure",
			"address": "AA:BB:CC:DD:EE:01",
			"model":   "Yuwell YE680B",
		},
		"measurements": []map[string]any{{
			"type":        "blood_pressure",
			"unit":        "mmHg",
			"recorded_at": "2026-11-27T08:15:09Z",
			"values":      map[string]any{"systolic": 120, "diastolic": 80, "pulse": 72},
		}},
	}
	first := do(t, srv, http.MethodPost, "/api/sync", payload)
	if first.Code != http.StatusOK {
		t.Fatalf("sync status %d body %s", first.Code, first.Body.String())
	}
	var syncBody map[string]int
	decode(t, first, &syncBody)
	if syncBody["inserted"] != 1 || syncBody["skipped"] != 0 {
		t.Fatalf("first sync %#v", syncBody)
	}
	second := do(t, srv, http.MethodPost, "/api/sync", payload)
	decode(t, second, &syncBody)
	if syncBody["inserted"] != 0 || syncBody["skipped"] != 1 {
		t.Fatalf("second sync %#v", syncBody)
	}

	list := do(t, srv, http.MethodGet, "/api/measurements?type=blood_pressure", nil)
	var items []map[string]any
	decode(t, list, &items)
	if len(items) != 1 {
		t.Fatalf("list len %d", len(items))
	}
	id := int64(items[0]["id"].(float64))

	updated := do(t, srv, http.MethodPut, "/api/measurements/"+strconv.FormatInt(id, 10), map[string]any{
		"type":        "blood_pressure",
		"unit":        "mmHg",
		"recorded_at": "2026-11-27T08:15:09Z",
		"values":      map[string]any{"systolic": 118, "diastolic": 76, "pulse": 70},
	})
	if updated.Code != http.StatusOK {
		t.Fatalf("update %d %s", updated.Code, updated.Body.String())
	}

	devices := do(t, srv, http.MethodGet, "/api/devices", nil)
	var deviceRows []map[string]any
	decode(t, devices, &deviceRows)
	if len(deviceRows) != 1 || deviceRows[0]["model"] != "Yuwell YE680B" {
		t.Fatalf("devices %#v", deviceRows)
	}
	deviceID := int64(deviceRows[0]["id"].(float64))
	renamed := do(t, srv, http.MethodPut, "/api/devices/"+strconv.FormatInt(deviceID, 10), map[string]any{
		"name":  "客厅血压计",
		"kind":  "blood_pressure",
		"model": "Yuwell YE680B",
	})
	if renamed.Code != http.StatusOK {
		t.Fatalf("rename %d %s", renamed.Code, renamed.Body.String())
	}

	bad := do(t, srv, http.MethodPost, "/api/measurements", map[string]any{
		"device_id":   deviceID,
		"type":        "not-a-type",
		"unit":        "bpm",
		"recorded_at": "2026-11-27T09:00:00Z",
		"values":      map[string]any{"bpm": 60},
	})
	if bad.Code != http.StatusBadRequest {
		t.Fatalf("invalid type status %d", bad.Code)
	}

	missing := do(t, srv, http.MethodGet, "/api/measurements/9999", nil)
	if missing.Code != http.StatusNotFound {
		t.Fatalf("missing status %d", missing.Code)
	}

	deleted := do(t, srv, http.MethodDelete, "/api/measurements/"+strconv.FormatInt(id, 10), nil)
	if deleted.Code != http.StatusNoContent {
		t.Fatalf("delete measurement %d", deleted.Code)
	}
	gone := do(t, srv, http.MethodDelete, "/api/devices/"+strconv.FormatInt(deviceID, 10), nil)
	if gone.Code != http.StatusNoContent {
		t.Fatalf("delete device %d", gone.Code)
	}
	after := do(t, srv, http.MethodGet, "/api/measurements", nil)
	decode(t, after, &items)
	if len(items) != 0 {
		t.Fatalf("measurements remain after device delete: %d", len(items))
	}
}

func testServer(t *testing.T) http.Handler {
	t.Helper()
	st, err := store.Open(filepath.Join(t.TempDir(), "api.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = st.Close() })
	if err := migrate.Up(st.DB()); err != nil {
		t.Fatal(err)
	}
	return New(st)
}

func do(t *testing.T, handler http.Handler, method, path string, body any) *httptest.ResponseRecorder {
	t.Helper()
	var buf bytes.Buffer
	if body != nil {
		if err := json.NewEncoder(&buf).Encode(body); err != nil {
			t.Fatal(err)
		}
	}
	req := httptest.NewRequest(method, path, &buf)
	req.Header.Set("Content-Type", "application/json")
	res := httptest.NewRecorder()
	handler.ServeHTTP(res, req)
	return res
}

func decode(t *testing.T, res *httptest.ResponseRecorder, dest any) {
	t.Helper()
	if err := json.Unmarshal(res.Body.Bytes(), dest); err != nil {
		t.Fatalf("decode %s: %v", res.Body.String(), err)
	}
}
