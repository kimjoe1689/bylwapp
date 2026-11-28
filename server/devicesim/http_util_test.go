package devicesim

import (
	"bytes"
	"encoding/json"
	"net/http"
	"testing"

	"github.com/kimjoe1689/bylwapp/server/schema"
)

func hashEvent(event any) (string, []byte, error) {
	return schema.PayloadHash(event.(schema.Event))
}

func postJSON(t *testing.T, url, token string, body any) *http.Response {
	t.Helper()
	buf, err := json.Marshal(body)
	if err != nil {
		t.Fatal(err)
	}
	req, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(buf))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = res.Body.Close() })
	if res.StatusCode >= 300 {
		t.Fatalf("%s %d", url, res.StatusCode)
	}
	return res
}

func decode(t *testing.T, res *http.Response, dest any) {
	t.Helper()
	if err := json.NewDecoder(res.Body).Decode(dest); err != nil {
		t.Fatal(err)
	}
}
