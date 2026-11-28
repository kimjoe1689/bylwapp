GO ?= go
export CGO_ENABLED = 0

.PHONY: run build test tidy

run:
	$(GO) run ./cmd/server

build:
	mkdir -p bin
	$(GO) build -o bin/bylw-server ./cmd/server

test:
	$(GO) test ./...

tidy:
	$(GO) mod tidy
