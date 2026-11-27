package main

import (
	"context"
	"errors"
	"flag"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/kimjoe1689/bylwapp/server/internal/config"
	"github.com/kimjoe1689/bylwapp/server/internal/httpapi"
	"github.com/kimjoe1689/bylwapp/server/internal/migrate"
	"github.com/kimjoe1689/bylwapp/server/internal/store"
)

func main() {
	logger := slog.New(slog.NewTextHandler(os.Stdout, nil))
	cfg, err := config.Load(os.Args[1:], os.Getenv, os.Stderr)
	if err != nil {
		if errors.Is(err, flag.ErrHelp) {
			os.Exit(0)
		}
		logger.Error("load config", "err", err)
		os.Exit(2)
	}

	st, err := store.Open(cfg.DBPath)
	if err != nil {
		logger.Error("open database", "err", err)
		os.Exit(1)
	}
	defer st.Close()
	if err := migrate.Up(st.DB()); err != nil {
		logger.Error("migrate", "err", err)
		os.Exit(1)
	}

	srv := &http.Server{
		Addr:              cfg.Addr,
		Handler:           httpapi.New(st),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = srv.Shutdown(shutdownCtx)
	}()

	logger.Info("listening", "addr", cfg.Addr, "db", cfg.DBPath)
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		logger.Error("server stopped", "err", err)
		os.Exit(1)
	}
}
