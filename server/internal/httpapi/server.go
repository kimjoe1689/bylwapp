package httpapi

import (
	"context"
	"crypto/rand"
	"encoding/csv"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/kimjoe1689/bylwapp/server/internal/store"
	"github.com/kimjoe1689/bylwapp/server/internal/web"
	"github.com/kimjoe1689/bylwapp/server/metrics"
	"github.com/kimjoe1689/bylwapp/server/schema"
)

// New builds the collector ingest API and caregiver dashboard.
// Missing credentials are rejected. Device tokens cannot read the dashboard,
// and caregiver tokens cannot ingest or administer devices.
func New(st *store.Store, staleAfter time.Duration) http.Handler {
	if staleAfter <= 0 {
		staleAfter = 15 * time.Minute
	}
	h := &handler{store: st, staleAfter: staleAfter}
	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.Recoverer)
	r.Use(middleware.Timeout(30 * time.Second))
	r.Use(cors)
	r.Get("/health", h.health)
	r.Get("/", web.Handler())
	r.Post("/api/v1/auth/login", h.login)
	r.Post("/api/v1/devices/register", h.registerDevice)
	r.Post("/api/v1/devices/{device_id}/events", h.ingest)
	r.Get("/api/v1/devices/{device_id}/events/{event_id}", h.readBack)

	r.Group(func(r chi.Router) {
		r.Use(h.requireUser)
		r.Get("/api/v1/dashboard/events", h.events)
		r.Get("/api/v1/dashboard/devices", h.devices)
		r.Get("/api/v1/dashboard/conflicts", h.conflicts)
		r.Get("/api/v1/dashboard/series", h.series)
		r.Get("/api/v1/exports/events.json", h.exportJSON)
		r.Get("/api/v1/exports/events.csv", h.exportCSV)
		r.Get("/api/v1/exports/reconciliation.json", h.exportReconciliation)
		r.Get("/api/v1/exports/rq1.json", h.exportRQ1)
		r.Get("/api/v1/exports/rq2.json", h.exportRQ2)
		r.Get("/api/v1/exports/rq3.json", h.exportRQ3)
		r.Get("/api/v1/exports/rq4.json", h.exportRQ4)
		r.Get("/api/v1/ground-truth", h.listGroundTruth)
		r.Post("/api/v1/ground-truth", h.addGroundTruth)
		r.Post("/api/v1/ground-truth/import", h.importGroundTruth)
		r.With(h.requireAdmin).Post("/api/v1/admin/users", h.createUser)
		r.With(h.requireAdmin).Post("/api/v1/admin/devices", h.createDevice)
		r.With(h.requireAdmin).Post("/api/v1/admin/devices/{device_id}/tokens", h.createToken)
	})
	return r
}

type handler struct {
	store      *store.Store
	staleAfter time.Duration
}

type principal struct {
	role     string
	deviceID string
}

func (h *handler) registerDevice(w http.ResponseWriter, r *http.Request) {
	var body struct {
		DeviceID string `json:"device_id"`
		Name     string `json:"name"`
	}
	if r.Body != nil {
		dec := json.NewDecoder(io.LimitReader(r.Body, 1<<20))
		if err := dec.Decode(&body); err != nil && !errors.Is(err, io.EOF) {
			writeError(w, http.StatusBadRequest, "invalid JSON")
			return
		}
	}
	id := strings.TrimSpace(body.DeviceID)
	if id == "" {
		id = "phone-" + strings.ReplaceAll(newID(), "-", "")
	}
	if !pathToken(id) {
		writeError(w, http.StatusBadRequest, "device_id must be a path-safe token")
		return
	}
	name := strings.TrimSpace(body.Name)
	if name == "" {
		name = "bylwapp"
	}
	if len(name) > 80 {
		name = name[:80]
	}
	if err := h.store.UpsertDevice(r.Context(), id, name); err != nil {
		writeError(w, http.StatusInternalServerError, "register failed")
		return
	}
	token, err := h.store.IssueDeviceToken(r.Context(), id)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "register failed")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]string{
		"token":     token,
		"device_id": id,
		"note":      "Store this token on the collector. It is not shown again.",
	})
}

func pathToken(value string) bool {
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

func newID() string {
	buf := make([]byte, 8)
	if _, err := rand.Read(buf); err != nil {
		return strings.ReplaceAll(time.Now().UTC().Format("20060102150405.000000000"), ".", "")
	}
	return hex.EncodeToString(buf)
}

func (h *handler) health(w http.ResponseWriter, r *http.Request) {
	if err := h.store.Ping(r.Context()); err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "degraded"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok", "time": time.Now().UTC().Format(time.RFC3339)})
}

func (h *handler) login(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if !decode(w, r, &body) {
		return
	}
	token, user, err := h.store.Login(r.Context(), strings.TrimSpace(body.Username), body.Password, 12*time.Hour)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "invalid credentials")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"token": token, "role": user.Role, "username": user.Username})
}

func (h *handler) ingest(w http.ResponseWriter, r *http.Request) {
	deviceID, ok := h.devicePrincipal(w, r)
	if !ok {
		return
	}
	if chi.URLParam(r, "device_id") != deviceID {
		writeError(w, http.StatusForbidden, "device token does not match the path")
		return
	}
	var body struct {
		Event       schema.Event `json:"event"`
		PayloadHash string       `json:"payload_hash"`
	}
	if !decode(w, r, &body) {
		return
	}
	event, err := schema.Prepare(body.Event)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if event.DeviceID != deviceID {
		writeError(w, http.StatusBadRequest, "event.device_id does not match the path")
		return
	}
	hash, canonical, err := schema.PayloadHash(event)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if !strings.EqualFold(strings.TrimSpace(body.PayloadHash), hash) {
		writeError(w, http.StatusBadRequest, "payload_hash does not match the canonical event")
		return
	}
	outcome, err := h.store.Ingest(r.Context(), event, hash, string(canonical))
	if err != nil {
		writeError(w, http.StatusInternalServerError, "ingest failed")
		return
	}
	status := http.StatusCreated
	switch outcome.Result {
	case "duplicate":
		status = http.StatusOK
	case "conflict":
		status = http.StatusConflict
	}
	writeJSON(w, status, map[string]any{
		"result":             outcome.Result,
		"event_id":           event.EventID,
		"payload_hash":       outcome.PayloadHash,
		"server_received_at": outcome.ServerReceivedAt.UTC().Format(time.RFC3339Nano),
	})
}

func (h *handler) readBack(w http.ResponseWriter, r *http.Request) {
	deviceID := chi.URLParam(r, "device_id")
	if user, ok := h.userIfAny(r); ok {
		if user.role != "admin" && user.role != "caregiver" {
			writeError(w, http.StatusForbidden, "forbidden")
			return
		}
	} else {
		tokenDevice, ok := h.devicePrincipal(w, r)
		if !ok {
			return
		}
		if tokenDevice != deviceID {
			writeError(w, http.StatusForbidden, "device token does not match the path")
			return
		}
	}
	item, err := h.store.GetEvent(r.Context(), deviceID, chi.URLParam(r, "event_id"))
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "read failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"result":             "stored",
		"event":              json.RawMessage(item.CanonicalJSON),
		"payload_hash":       item.PayloadHash,
		"server_received_at": item.ServerReceivedAt.UTC().Format(time.RFC3339Nano),
	})
}

func (h *handler) events(w http.ResponseWriter, r *http.Request) {
	items, err := h.store.ListEvents(r.Context(), 100)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "list failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"note":   "最近 100 条是可见性视图，不是丢失清单，也不是论文第四章的结果。",
		"events": items,
	})
}

func (h *handler) devices(w http.ResponseWriter, r *http.Request) {
	items, err := h.store.DeviceStatuses(r.Context(), h.staleAfter)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "status failed")
		return
	}
	writeJSON(w, http.StatusOK, items)
}

func (h *handler) conflicts(w http.ResponseWriter, r *http.Request) {
	items, err := h.store.Conflicts(r.Context(), 100)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "conflicts failed")
		return
	}
	writeJSON(w, http.StatusOK, items)
}

func (h *handler) series(w http.ResponseWriter, r *http.Request) {
	kind := r.URL.Query().Get("type")
	if kind == "" {
		writeError(w, http.StatusBadRequest, "type is required")
		return
	}
	points, err := h.store.Series(r.Context(), r.URL.Query().Get("device_id"), kind, 100)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "series failed")
		return
	}
	writeJSON(w, http.StatusOK, points)
}

func (h *handler) exportJSON(w http.ResponseWriter, r *http.Request) {
	items, err := h.store.ListAllEvents(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "export failed")
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Content-Disposition", `attachment; filename="events.json"`)
	_ = json.NewEncoder(w).Encode(map[string]any{
		"note":   "Raw server receipt log. Not a Chapter 4 result.",
		"events": items,
	})
}

func (h *handler) exportCSV(w http.ResponseWriter, r *http.Request) {
	items, err := h.store.ListAllEvents(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "export failed")
		return
	}
	w.Header().Set("Content-Type", "text/csv; charset=utf-8")
	w.Header().Set("Content-Disposition", `attachment; filename="events.csv"`)
	cw := csv.NewWriter(w)
	_ = cw.Write([]string{"server_received_at", "device_id", "event_id", "payload_hash", "measurement_type", "unit", "sensor_address", "sensor_kind", "sensor_model", "monotonic_us", "wall_time_utc", "clock_state", "operating_state", "values_json"})
	for _, item := range items {
		wall := ""
		if item.Event.WallTimeUTC != nil {
			wall = *item.Event.WallTimeUTC
		}
		values, _ := json.Marshal(item.Event.Values)
		_ = cw.Write([]string{
			item.ServerReceivedAt.UTC().Format(time.RFC3339Nano),
			item.Event.DeviceID, item.Event.EventID, item.PayloadHash, item.Event.MeasurementType, item.Event.Unit,
			item.Event.SensorAddress, item.Event.SensorKind, item.Event.SensorModel,
			itoa(item.Event.MonotonicUS), wall, item.Event.ClockState, item.Event.OperatingState, string(values),
		})
	}
	cw.Flush()
}

func (h *handler) exportReconciliation(w http.ResponseWriter, r *http.Request) {
	stored, duplicates, conflicts, err := h.store.Counts(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "reconciliation failed")
		return
	}
	rows, err := h.store.Conflicts(r.Context(), 500)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "reconciliation failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"note": "Server-side receipt reconciliation. Duplicate and conflict counts are ingest attempts. This file does not estimate data loss and is not a Chapter 4 result.",
		"counts": map[string]int{
			"stored_events":  stored,
			"duplicate_acks": duplicates,
			"conflicts":      conflicts,
		},
		"conflicts": rows,
	})
}

func (h *handler) reports(r *http.Request) (metrics.RQ1, metrics.RQ2, metrics.RQ3, metrics.RQ4, error) {
	events, ledger, err := h.store.Evidence(r.Context())
	if err != nil {
		return metrics.RQ1{}, metrics.RQ2{}, metrics.RQ3{}, metrics.RQ4{}, err
	}
	stored, duplicates, conflicts, err := h.store.Counts(r.Context())
	if err != nil {
		return metrics.RQ1{}, metrics.RQ2{}, metrics.RQ3{}, metrics.RQ4{}, err
	}
	return metrics.SummarizeRQ1(events, ledger), metrics.SummarizeRQ2(events, ledger), metrics.SummarizeRQ3(stored, duplicates, conflicts), metrics.SummarizeRQ4(events), nil
}

func (h *handler) exportRQ1(w http.ResponseWriter, r *http.Request) {
	rq1, _, _, _, err := h.reports(r)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "rq1 failed")
		return
	}
	writeJSON(w, http.StatusOK, rq1)
}

func (h *handler) exportRQ2(w http.ResponseWriter, r *http.Request) {
	_, rq2, _, _, err := h.reports(r)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "rq2 failed")
		return
	}
	writeJSON(w, http.StatusOK, rq2)
}

func (h *handler) exportRQ3(w http.ResponseWriter, r *http.Request) {
	_, _, rq3, _, err := h.reports(r)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "rq3 failed")
		return
	}
	writeJSON(w, http.StatusOK, rq3)
}

func (h *handler) exportRQ4(w http.ResponseWriter, r *http.Request) {
	_, _, _, rq4, err := h.reports(r)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "rq4 failed")
		return
	}
	writeJSON(w, http.StatusOK, rq4)
}

func (h *handler) listGroundTruth(w http.ResponseWriter, r *http.Request) {
	rows, err := h.store.ListGroundTruth(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "ledger failed")
		return
	}
	writeJSON(w, http.StatusOK, rows)
}

func (h *handler) addGroundTruth(w http.ResponseWriter, r *http.Request) {
	var body store.GroundTruth
	if !decode(w, r, &body) {
		return
	}
	if body.ObservedAt.IsZero() {
		body.ObservedAt = time.Now().UTC()
	}
	if body.DeviceID == "" || body.MatchKey == "" || body.ReferenceType == "" || body.Observer == "" {
		writeError(w, http.StatusBadRequest, "device_id, match_key, reference_type, and observer are required")
		return
	}
	if err := h.store.AddGroundTruth(r.Context(), body); err != nil {
		writeError(w, http.StatusBadRequest, "could not save ground truth")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]string{"status": "stored"})
}

func (h *handler) importGroundTruth(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	rows, err := csv.NewReader(r.Body).ReadAll()
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid CSV")
		return
	}
	saved := 0
	for i, row := range rows {
		if i == 0 && len(row) > 0 && row[0] == "device_id" {
			continue
		}
		if len(row) < 6 {
			continue
		}
		observed, err := time.Parse(time.RFC3339, row[4])
		if err != nil {
			writeError(w, http.StatusBadRequest, "observed_at must be RFC3339")
			return
		}
		notes := ""
		if len(row) > 6 {
			notes = row[6]
		}
		if err := h.store.AddGroundTruth(r.Context(), store.GroundTruth{
			DeviceID: row[0], MatchKey: row[1], ReferenceType: row[2], ReferenceValue: row[3],
			ObservedAt: observed, Observer: row[5], Notes: notes,
		}); err != nil {
			writeError(w, http.StatusBadRequest, "could not import a row")
			return
		}
		saved++
	}
	writeJSON(w, http.StatusCreated, map[string]int{"imported": saved})
}

func (h *handler) createUser(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Username string `json:"username"`
		Password string `json:"password"`
		Role     string `json:"role"`
	}
	if !decode(w, r, &body) {
		return
	}
	if len(body.Password) < 8 {
		writeError(w, http.StatusBadRequest, "password must be at least 8 characters")
		return
	}
	if err := h.store.CreateUser(r.Context(), strings.TrimSpace(body.Username), body.Password, body.Role, 0); err != nil {
		writeError(w, http.StatusBadRequest, "could not create user")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]string{"username": body.Username, "role": body.Role})
}

func (h *handler) createDevice(w http.ResponseWriter, r *http.Request) {
	var body struct {
		DeviceID string `json:"device_id"`
		Name     string `json:"name"`
	}
	if !decode(w, r, &body) {
		return
	}
	if err := h.store.UpsertDevice(r.Context(), strings.TrimSpace(body.DeviceID), strings.TrimSpace(body.Name)); err != nil {
		writeError(w, http.StatusBadRequest, "could not save device")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]string{"device_id": body.DeviceID, "name": body.Name})
}

func (h *handler) createToken(w http.ResponseWriter, r *http.Request) {
	token, err := h.store.IssueDeviceToken(r.Context(), chi.URLParam(r, "device_id"))
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "device not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "token failed")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]string{
		"token": token,
		"note":  "Store this token on the collector. It is not shown again.",
	})
}

func (h *handler) requireUser(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		user, ok := h.userIfAny(r)
		if !ok {
			writeError(w, http.StatusUnauthorized, "login required")
			return
		}
		next.ServeHTTP(w, r.WithContext(withPrincipal(r.Context(), user)))
	})
}

func (h *handler) requireAdmin(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		user, _ := principalFrom(r.Context())
		if user.role != "admin" {
			writeError(w, http.StatusForbidden, "admin required")
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (h *handler) devicePrincipal(w http.ResponseWriter, r *http.Request) (string, bool) {
	token := bearer(r)
	if token == "" {
		writeError(w, http.StatusUnauthorized, "device token required")
		return "", false
	}
	deviceID, err := h.store.DeviceByToken(r.Context(), token)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "device token rejected")
		return "", false
	}
	return deviceID, true
}

func (h *handler) userIfAny(r *http.Request) (principal, bool) {
	token := bearer(r)
	if token == "" {
		return principal{}, false
	}
	user, err := h.store.UserByToken(r.Context(), token)
	if err != nil {
		return principal{}, false
	}
	return principal{role: user.Role}, true
}

func bearer(r *http.Request) string {
	value := r.Header.Get("Authorization")
	const prefix = "Bearer "
	if !strings.HasPrefix(value, prefix) {
		return ""
	}
	return strings.TrimSpace(strings.TrimPrefix(value, prefix))
}

func decode(w http.ResponseWriter, r *http.Request, dest any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	if err := json.NewDecoder(r.Body).Decode(dest); err != nil && !errors.Is(err, io.EOF) {
		writeError(w, http.StatusBadRequest, "invalid JSON")
		return false
	}
	return true
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

type ctxKey int

const principalKey ctxKey = 1

func withPrincipal(ctx context.Context, user principal) context.Context {
	return context.WithValue(ctx, principalKey, user)
}

func principalFrom(ctx context.Context) (principal, bool) {
	user, ok := ctx.Value(principalKey).(principal)
	return user, ok
}

func itoa(value int64) string {
	return strconvFormat(value)
}

func strconvFormat(value int64) string {
	if value == 0 {
		return "0"
	}
	var buf [20]byte
	i := len(buf)
	neg := value < 0
	if neg {
		value = -value
	}
	for value > 0 {
		i--
		buf[i] = byte('0' + value%10)
		value /= 10
	}
	if neg {
		i--
		buf[i] = '-'
	}
	return string(buf[i:])
}
