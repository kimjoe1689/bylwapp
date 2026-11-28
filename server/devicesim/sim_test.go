package devicesim

import (
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"

	"github.com/kimjoe1689/bylwapp/server/internal/httpapi"
	"github.com/kimjoe1689/bylwapp/server/internal/migrate"
	"github.com/kimjoe1689/bylwapp/server/internal/store"
	"golang.org/x/crypto/bcrypt"
)

func TestScenarios(t *testing.T) {
	httpServer, token := newServer(t)
	defer httpServer.Close()

	t.Run("nominal", func(t *testing.T) {
		journal := &Journal{}
		event, err := SampleBloodPressure("phone-1", "evt-nominal", 0)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := journal.Add(event); err != nil {
			t.Fatal(err)
		}
		if err := SyncOnce(t.Context(), journal, HTTPGateway{BaseURL: httpServer.URL, Token: token}); err != nil {
			t.Fatal(err)
		}
		if journal.Records[0].State != StateSynced {
			t.Fatalf("state %s %s", journal.Records[0].State, journal.Records[0].LastError)
		}
	})

	t.Run("duplicate", func(t *testing.T) {
		journal := &Journal{}
		event, _ := SampleBloodPressure("phone-1", "evt-dup", 0)
		record, _ := journal.Add(event)
		gateway := HTTPGateway{BaseURL: httpServer.URL, Token: token}
		if err := SyncOnce(t.Context(), journal, gateway); err != nil {
			t.Fatal(err)
		}
		record.State = StatePending
		if err := SyncOnce(t.Context(), journal, gateway); err != nil {
			t.Fatal(err)
		}
		if record.State != StateSynced {
			t.Fatalf("duplicate should still be synced, got %s", record.State)
		}
	})

	t.Run("outage then recovery", func(t *testing.T) {
		journal := &Journal{}
		event, _ := SampleBloodPressure("phone-1", "evt-outage", 0)
		record, _ := journal.Add(event)
		down := HTTPGateway{BaseURL: httpServer.URL, Token: token, NetworkDown: true}
		if err := SyncOnce(t.Context(), journal, down); err != nil {
			t.Fatal(err)
		}
		if record.State != StatePending {
			t.Fatalf("outage state %s", record.State)
		}
		if err := SyncOnce(t.Context(), journal, HTTPGateway{BaseURL: httpServer.URL, Token: token}); err != nil {
			t.Fatal(err)
		}
		if record.State != StateSynced {
			t.Fatalf("recovery state %s %s", record.State, record.LastError)
		}
	})

	t.Run("timeout after commit", func(t *testing.T) {
		journal := &Journal{}
		event, _ := SampleBloodPressure("phone-1", "evt-timeout", 0)
		record, _ := journal.Add(event)
		gateway := HTTPGateway{BaseURL: httpServer.URL, Token: token, DropReply: true}
		if err := SyncOnce(t.Context(), journal, gateway); err != nil {
			t.Fatal(err)
		}
		if record.State != StateSynced {
			t.Fatalf("read-back state %s %s", record.State, record.LastError)
		}
	})

	t.Run("clock skew is stored", func(t *testing.T) {
		journal := &Journal{}
		event, err := SampleBloodPressure("phone-1", "evt-skew", 6*time.Hour)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := journal.Add(event); err != nil {
			t.Fatal(err)
		}
		if err := SyncOnce(t.Context(), journal, HTTPGateway{BaseURL: httpServer.URL, Token: token}); err != nil {
			t.Fatal(err)
		}
		if journal.Records[0].State != StateSynced || journal.Records[0].Event.OperatingState != "CLOCK_DEGRADED" {
			t.Fatalf("skew %+v", journal.Records[0])
		}
	})

	t.Run("conflict keeps first", func(t *testing.T) {
		journal := &Journal{}
		event, _ := SampleBloodPressure("phone-1", "evt-conflict", 0)
		first, _ := journal.Add(event)
		if err := SyncOnce(t.Context(), journal, HTTPGateway{BaseURL: httpServer.URL, Token: token}); err != nil {
			t.Fatal(err)
		}
		event.Values = map[string]any{"systolic": 200.0, "diastolic": 90.0, "pulse": 70.0}
		second, err := journal.Add(event)
		if err != nil {
			t.Fatal(err)
		}
		second.Event.EventID = first.Event.EventID
		hash, body, err := schemaHash(second.Event)
		if err != nil {
			t.Fatal(err)
		}
		second.Hash, second.Canonical = hash, string(body)
		if err := SyncOnce(t.Context(), journal, HTTPGateway{BaseURL: httpServer.URL, Token: token}); err != nil {
			t.Fatal(err)
		}
		if second.State != StateConflict || first.State != StateSynced {
			t.Fatalf("first %s second %s", first.State, second.State)
		}
	})
}

func schemaHash(event interface{}) (string, []byte, error) {
	return hashEvent(event)
}

func newServer(t *testing.T) (*httptest.Server, string) {
	t.Helper()
	st, err := store.Open(filepath.Join(t.TempDir(), "sim.db"))
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
	handler := httpapi.New(st, time.Minute)
	ts := httptest.NewServer(handler)
	loginRes := postJSON(t, ts.URL+"/api/v1/auth/login", "", map[string]string{"username": "admin", "password": "admin-pass-1"})
	var login map[string]string
	decode(t, loginRes, &login)
	_ = postJSON(t, ts.URL+"/api/v1/admin/devices", login["token"], map[string]string{"device_id": "phone-1", "name": "sim"})
	tokenRes := postJSON(t, ts.URL+"/api/v1/admin/devices/phone-1/tokens", login["token"], map[string]string{})
	var issued map[string]string
	decode(t, tokenRes, &issued)
	return ts, issued["token"]
}
