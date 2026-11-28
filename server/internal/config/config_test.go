package config

import (
	"bytes"
	"testing"
)

func TestLoadDefaultsAndPrecedence(t *testing.T) {
	cfg, err := Load(nil, func(string) string { return "" }, &bytes.Buffer{})
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Addr != ":8080" || cfg.DBPath != "data/bylw.db" {
		t.Fatalf("defaults: %+v", cfg)
	}

	cfg, err = Load(nil, func(key string) string {
		switch key {
		case "BYLW_ADDR":
			return ":9090"
		case "BYLW_DB":
			return "tmp/app.db"
		default:
			return ""
		}
	}, &bytes.Buffer{})
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Addr != ":9090" || cfg.DBPath != "tmp/app.db" {
		t.Fatalf("env: %+v", cfg)
	}

	cfg, err = Load([]string{"-addr", ":7070"}, func(key string) string {
		if key == "BYLW_ADDR" {
			return ":9090"
		}
		return ""
	}, &bytes.Buffer{})
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Addr != ":7070" || cfg.DBPath != "data/bylw.db" {
		t.Fatalf("flag should override env: %+v", cfg)
	}
}

func TestLoadRejectsEmpty(t *testing.T) {
	_, err := Load([]string{"-addr", "  "}, func(string) string { return "" }, &bytes.Buffer{})
	if err == nil {
		t.Fatal("expected error for empty addr")
	}
}
