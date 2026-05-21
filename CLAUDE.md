# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MediaMTX (`github.com/bluenviron/mediamtx`) is a zero-dependency real-time media server / media proxy written in Go. It ingests and serves live streams over SRT, WebRTC, RTSP, RTMP, HLS, MPEG-TS and RTP, automatically converting between protocols, and supports recording and playback to/from disk.

This checkout is a fork: the upstream codebase plus custom CI in `.github/workflows/` that builds a custom-ffmpeg Docker image and deploys the container to an EC2 host over SSH.

## Build & Run

```bash
go build -o mediamtx .          # build the single binary
./mediamtx [mediamtx.yml]       # run; reads mediamtx.yml from cwd by default
go generate ./...               # regenerate embedded assets (run before tests)
```

`main.go` is a thin wrapper; all logic starts at `core.New()` in `internal/core/core.go`.

## Test / Lint / Format

The `Makefile` targets run inside Docker for reproducibility. Use the `-nodocker` variants to run directly on the host (faster, requires a local Go toolchain):

```bash
make test                       # full test suite in Docker
make test-nodocker              # test-internal + test-core directly on host
make test-e2e-nodocker          # e2e tests (needs Docker daemon; -tags enable_e2e_tests)
make lint                       # all linters (golangci-lint + conf/api/docs linters)
make format                     # gofumpt + prettier

# Run a single test directly:
go test -run TestName ./internal/conf
go test -v -race ./internal/core -run TestAPI
```

Notes:
- `make test-internal` covers `./internal/...` except `/core`; `make test-core` covers `./internal/core` (the integration-heavy package). Tests are split because core tests are slow.
- The custom linters under `internal/linters/` require the `enable_linters` build tag (e.g. `go test -tags enable_linters ./internal/linters/conf`). They validate that config struct, OpenAPI spec, and docs stay in sync.
- `go.mod` requires Go 1.26.

## Architecture

A single process wires everything together in `internal/core/core.go`. Key flow:

- **`core`** parses config, sets up logging/metrics/pprof, and owns the lifecycle of all servers and the path manager. It hot-reloads on config file changes via `internal/confwatcher`.
- **`pathManager`** (`internal/core/path_manager.go`) is the central registry. A **path** (`internal/core/path.go`) is a named stream slot; each path has at most one publisher and many readers. Protocol servers and static sources attach to paths through the path manager.
- **`internal/servers/{rtsp,rtmp,hls,webrtc,srt}`** — one server per protocol for *incoming* publishers and *outgoing* readers. They are protocol front-ends; the actual stream data lives in a path.
- **`internal/staticsources/`** — pull-based sources (the server connects out to fetch a stream): RTSP/RTMP/HLS/SRT/RTP clients, plus `rpicamera`. Used for "always-available" paths configured with a `source:` URL.
- **`internal/stream`** + **`internal/unit`** — the codec-agnostic in-memory stream abstraction; media units flow from a publisher through `stream` to all readers, with per-protocol formats resolved via `internal/defs` and `internal/formatlabel`.
- **`internal/protocols/`** — lower-level protocol implementations (hls, rtsp, rtmp, webrtc, whip, mpegts, websocket, httpp, tls, udp, unix) shared by servers and static sources.
- **`internal/recorder`** + **`internal/recordstore`** + **`internal/playback`** — write streams to fMP4/MPEG-TS segments on disk and serve them back. `recordcleaner` deletes expired segments.
- **`internal/conf`** — the full configuration model. `conf.go` is the global config; `path.go` is per-path config; many small files define typed config values (durations, sizes, auth methods, etc.). Changing config means touching this package *and* keeping `api/openapi.yaml` and `docs/` in sync (enforced by the linters above).
- **`internal/api`** — the Control API (HTTP/JSON), spec'd in `api/openapi.yaml`.
- **`internal/auth`** — internal / HTTP / JWT authentication.
- **`internal/hooks`** + **`internal/externalcmd`** — run external commands on connect/disconnect/read/publish events.

`mediamtx.yml` is the canonical, fully-commented example config; its structure mirrors `internal/conf`.

## Conventions

- New code must pass `gofumpt` (stricter than `gofmt`) — run `make format`.
- When adding or changing a config option: update `internal/conf`, `mediamtx.yml`, `api/openapi.yaml`, and the relevant `docs/` page together, or `make lint` will fail.
- Test helpers/fixtures live in `internal/test`; e2e tests live in `internal/teste2e`.
