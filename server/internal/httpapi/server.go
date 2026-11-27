// Package httpapi is the admin JSON API and page router.
package httpapi

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/kimjoe1689/bylwapp/server/internal/store"
	"github.com/kimjoe1689/bylwapp/server/internal/web"
)

const maxSyncBatch = 500

var deviceKinds = map[string]struct{}{
	"blood_pressure": {},
	"heart_rate":     {},
	"ring":           {},
}

var measurementTypes = map[string]struct{}{
	"blood_pressure": {},
	"heart_rate":     {},
	"steps":          {},
	"spo2":           {},
	"sleep":          {},
	"sleep_session":  {},
	"stress":         {},
	"hrv":            {},
	"temperature":    {},
}

// New builds the HTTP handler. The store must already be migrated.
func New(st *store.Store) http.Handler {
	api := &handler{store: st}
	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Recoverer)
	r.Use(middleware.Timeout(30 * time.Second))
	r.Use(cors)

	r.Get("/health", api.health)
	r.Get("/", web.Handler())
	r.Get("/admin", web.Handler())

	r.Get("/api/devices", api.listDevices)
	r.Post("/api/devices", api.createDevice)
	r.Get("/api/devices/{id}", api.getDevice)
	r.Put("/api/devices/{id}", api.updateDevice)
	r.Delete("/api/devices/{id}", api.deleteDevice)

	r.Get("/api/measurements", api.listMeasurements)
	r.Post("/api/measurements", api.createMeasurement)
	r.Get("/api/measurements/{id}", api.getMeasurement)
	r.Put("/api/measurements/{id}", api.updateMeasurement)
	r.Delete("/api/measurements/{id}", api.deleteMeasurement)

	r.Post("/api/sync", api.sync)
	return r
}

type handler struct {
	store *store.Store
}

func (h *handler) health(w http.ResponseWriter, r *http.Request) {
	if err := h.store.Ping(r.Context()); err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "degraded"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{
		"status": "ok",
		"time":   time.Now().UTC().Format(time.RFC3339),
	})
}

func (h *handler) listDevices(w http.ResponseWriter, r *http.Request) {
	devices, err := h.store.ListDevices(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "list devices failed")
		return
	}
	writeJSON(w, http.StatusOK, devices)
}

func (h *handler) createDevice(w http.ResponseWriter, r *http.Request) {
	body, err := decodeDevice(w, r)
	if err != nil {
		return
	}
	device, err := h.store.CreateDevice(r.Context(), body.Name, body.Kind, body.Address, body.Model)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, device)
}

func (h *handler) getDevice(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	device, err := h.store.GetDevice(r.Context(), id)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, device)
}

func (h *handler) updateDevice(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var body struct {
		Name  string `json:"name"`
		Kind  string `json:"kind"`
		Model string `json:"model"`
	}
	if err := readJSON(w, r, &body); err != nil {
		return
	}
	name, kind, model, err := normalizeDeviceUpdate(body.Name, body.Kind, body.Model)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	device, err := h.store.UpdateDevice(r.Context(), id, name, kind, model)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, device)
}

func (h *handler) deleteDevice(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	if err := h.store.DeleteDevice(r.Context(), id); err != nil {
		writeStoreError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *handler) listMeasurements(w http.ResponseWriter, r *http.Request) {
	filter, err := measurementFilter(r)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	items, err := h.store.ListMeasurements(r.Context(), filter)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "list measurements failed")
		return
	}
	writeJSON(w, http.StatusOK, items)
}

func (h *handler) createMeasurement(w http.ResponseWriter, r *http.Request) {
	body, err := decodeMeasurementBody(w, r, true)
	if err != nil {
		return
	}
	item, err := h.store.CreateMeasurement(r.Context(), body.DeviceID, body.Input)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, item)
}

func (h *handler) getMeasurement(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	item, err := h.store.GetMeasurement(r.Context(), id)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, item)
}

func (h *handler) updateMeasurement(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	body, err := decodeMeasurementBody(w, r, false)
	if err != nil {
		return
	}
	item, err := h.store.UpdateMeasurement(r.Context(), id, body.Input)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, item)
}

func (h *handler) deleteMeasurement(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	if err := h.store.DeleteMeasurement(r.Context(), id); err != nil {
		writeStoreError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *handler) sync(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Device struct {
			Name    string `json:"name"`
			Kind    string `json:"kind"`
			Address string `json:"address"`
			Model   string `json:"model"`
		} `json:"device"`
		Measurements []measurementPayload `json:"measurements"`
	}
	if err := readJSON(w, r, &body); err != nil {
		return
	}
	name, kind, address, model, err := normalizeDevice(body.Device.Name, body.Device.Kind, body.Device.Address, body.Device.Model)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if len(body.Measurements) > maxSyncBatch {
		writeError(w, http.StatusBadRequest, "too many measurements")
		return
	}
	items := make([]store.MeasurementInput, 0, len(body.Measurements))
	for _, raw := range body.Measurements {
		item, err := normalizeMeasurement(raw)
		if err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		items = append(items, item)
	}
	result, err := h.store.SyncDeviceMeasurements(r.Context(), name, kind, address, model, items)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, result)
}

type devicePayload struct {
	Name    string `json:"name"`
	Kind    string `json:"kind"`
	Address string `json:"address"`
	Model   string `json:"model"`
}

type measurementPayload struct {
	Type       string          `json:"type"`
	Unit       string          `json:"unit"`
	RecordedAt time.Time       `json:"recorded_at"`
	Values     json.RawMessage `json:"values"`
}

type measurementBody struct {
	DeviceID int64 `json:"device_id"`
	measurementPayload
	Input store.MeasurementInput
}

func decodeDevice(w http.ResponseWriter, r *http.Request) (devicePayload, error) {
	var body devicePayload
	if err := readJSON(w, r, &body); err != nil {
		return devicePayload{}, err
	}
	name, kind, address, model, err := normalizeDevice(body.Name, body.Kind, body.Address, body.Model)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return devicePayload{}, err
	}
	body.Name, body.Kind, body.Address, body.Model = name, kind, address, model
	return body, nil
}

func decodeMeasurementBody(w http.ResponseWriter, r *http.Request, requireDevice bool) (measurementBody, error) {
	var body measurementBody
	if err := readJSON(w, r, &body); err != nil {
		return measurementBody{}, err
	}
	if requireDevice && body.DeviceID <= 0 {
		writeError(w, http.StatusBadRequest, "device_id is required")
		return measurementBody{}, errors.New("device_id is required")
	}
	item, err := normalizeMeasurement(body.measurementPayload)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return measurementBody{}, err
	}
	body.Input = item
	return body, nil
}

func normalizeDevice(name, kind, address, model string) (string, string, string, string, error) {
	name, kind, model, err := normalizeDeviceUpdate(name, kind, model)
	if err != nil {
		return "", "", "", "", err
	}
	address = strings.TrimSpace(address)
	if address == "" || len(address) > 80 {
		return "", "", "", "", errors.New("address is required")
	}
	return name, kind, address, model, nil
}

func normalizeDeviceUpdate(name, kind, model string) (string, string, string, error) {
	name = strings.TrimSpace(name)
	kind = strings.TrimSpace(kind)
	model = strings.TrimSpace(model)
	if name == "" || len(name) > 80 {
		return "", "", "", errors.New("name is required")
	}
	if _, ok := deviceKinds[kind]; !ok {
		return "", "", "", errors.New("kind must be blood_pressure, heart_rate, or ring")
	}
	if len(model) > 80 {
		return "", "", "", errors.New("model is too long")
	}
	return name, kind, model, nil
}

func normalizeMeasurement(raw measurementPayload) (store.MeasurementInput, error) {
	raw.Type = strings.TrimSpace(raw.Type)
	raw.Unit = strings.TrimSpace(raw.Unit)
	if _, ok := measurementTypes[raw.Type]; !ok {
		return store.MeasurementInput{}, errors.New("unknown measurement type")
	}
	if raw.Unit == "" || len(raw.Unit) > 16 {
		return store.MeasurementInput{}, errors.New("unit is required")
	}
	if raw.RecordedAt.IsZero() {
		return store.MeasurementInput{}, errors.New("recorded_at is required")
	}
	trimmed := strings.TrimSpace(string(raw.Values))
	if trimmed == "" || !json.Valid([]byte(trimmed)) || trimmed[0] != '{' {
		return store.MeasurementInput{}, errors.New("values must be a JSON object")
	}
	return store.MeasurementInput{
		Type:       raw.Type,
		Unit:       raw.Unit,
		RecordedAt: raw.RecordedAt.UTC(),
		Values:     raw.Values,
	}, nil
}

func measurementFilter(r *http.Request) (store.MeasurementFilter, error) {
	var filter store.MeasurementFilter
	q := r.URL.Query()
	if raw := q.Get("device_id"); raw != "" {
		id, err := strconv.ParseInt(raw, 10, 64)
		if err != nil || id <= 0 {
			return filter, errors.New("invalid device_id")
		}
		filter.DeviceID = &id
	}
	filter.Type = strings.TrimSpace(q.Get("type"))
	if filter.Type != "" {
		if _, ok := measurementTypes[filter.Type]; !ok {
			return filter, errors.New("unknown measurement type")
		}
	}
	if raw := q.Get("from"); raw != "" {
		t, err := time.Parse(time.RFC3339, raw)
		if err != nil {
			return filter, errors.New("invalid from")
		}
		filter.From = &t
	}
	if raw := q.Get("to"); raw != "" {
		t, err := time.Parse(time.RFC3339, raw)
		if err != nil {
			return filter, errors.New("invalid to")
		}
		filter.To = &t
	}
	if raw := q.Get("limit"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n <= 0 {
			return filter, errors.New("invalid limit")
		}
		filter.Limit = n
	}
	return filter, nil
}

func pathID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id <= 0 {
		writeError(w, http.StatusBadRequest, "invalid id")
		return 0, false
	}
	return id, true
}

func readJSON(w http.ResponseWriter, r *http.Request, dest any) error {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	dec := json.NewDecoder(r.Body)
	if err := dec.Decode(dest); err != nil {
		writeError(w, http.StatusBadRequest, "invalid JSON")
		return err
	}
	return nil
}

func writeStoreError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, store.ErrNotFound):
		writeError(w, http.StatusNotFound, "not found")
	case strings.Contains(err.Error(), "already exists"):
		writeError(w, http.StatusConflict, err.Error())
	default:
		writeError(w, http.StatusInternalServerError, "request failed")
	}
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
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
