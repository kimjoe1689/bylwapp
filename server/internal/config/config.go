// Package config loads bylw-server settings from flags and environment variables.
package config

import (
	"errors"
	"flag"
	"io"
	"strings"
)

// Config is the process configuration.
type Config struct {
	Addr   string
	DBPath string
}

// Load reads configuration. Flags override environment variables, which override defaults.
// BYLW_ADDR sets the listen address (default ":8080"). BYLW_DB sets the SQLite path
// (default "data/bylw.db").
func Load(args []string, getenv func(string) string, output io.Writer) (Config, error) {
	if getenv == nil {
		getenv = func(string) string { return "" }
	}
	fs := flag.NewFlagSet("bylw-server", flag.ContinueOnError)
	fs.SetOutput(output)
	addr := fs.String("addr", firstNonEmpty(getenv("BYLW_ADDR"), ":8080"), "HTTP 监听地址")
	dbPath := fs.String("db", firstNonEmpty(getenv("BYLW_DB"), "data/bylw.db"), "SQLite 数据库文件路径")
	if err := fs.Parse(args); err != nil {
		return Config{}, err
	}
	cfg := Config{
		Addr:   strings.TrimSpace(*addr),
		DBPath: strings.TrimSpace(*dbPath),
	}
	if cfg.Addr == "" || cfg.DBPath == "" {
		return Config{}, errors.New("addr and db are required")
	}
	return cfg, nil
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}
