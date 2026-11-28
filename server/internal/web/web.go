// Package web serves the embedded admin page.
package web

import (
	"embed"
	"net/http"
)

//go:embed index.html
var assets embed.FS

// Handler serves the admin UI.
func Handler() http.HandlerFunc {
	page, err := assets.ReadFile("index.html")
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		if err != nil {
			http.Error(w, "admin page missing", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Header().Set("Cache-Control", "no-cache")
		_, _ = w.Write(page)
	}
}
