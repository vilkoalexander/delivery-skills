# Sources

References behind `CHECKLIST.md`. Not loaded during a review. Checked
2026-11-25: Go 1.27.4 and 1.26.11 are the supported releases, Go 1.28 is a
draft for February 2027.

- [Go release history](https://go.dev/doc/devel/release) and the release notes [1.20](https://go.dev/doc/go1.20), [1.21](https://go.dev/doc/go1.21), [1.22](https://go.dev/doc/go1.22), [1.23](https://go.dev/doc/go1.23), [1.24](https://go.dev/doc/go1.24), [1.25](https://go.dev/doc/go1.25), [1.26](https://go.dev/doc/go1.26), [1.27](https://go.dev/doc/go1.27), [1.28 draft](https://tip.golang.org/doc/go1.28) — the version baseline table
- [Working with errors in Go 1.13](https://go.dev/blog/go1.13-errors) — `%w`, `errors.Is`, `errors.As`, when wrapping makes an error part of the API
- [Why is my nil error value not equal to nil?](https://go.dev/doc/faq#nil_error) — a typed nil pointer in an `error`
- [package context](https://pkg.go.dev/context) and [Contexts and structs](https://go.dev/blog/context-and-structs) — first parameter, never stored, always cancel, `WithoutCancel`, the `Cause` variants
- [package net/http](https://pkg.go.dev/net/http) — no default timeouts on `Server` or `Client`, `MaxBytesReader`, `Shutdown`, "the caller must close the response body", `ResponseController`, `CrossOriginProtection`
- [package os/signal — NotifyContext](https://pkg.go.dev/os/signal#NotifyContext)
- [package database/sql](https://pkg.go.dev/database/sql), [Querying for data](https://go.dev/doc/database/querying), [Executing transactions](https://go.dev/doc/database/execute-transactions), [Avoiding SQL injection risk](https://go.dev/doc/database/sql-injection) — `Rows.Close`, `Rows.Err`, the deferred rollback
- [Go Concurrency Patterns: Pipelines and cancellation](https://go.dev/blog/pipelines), [The Go Memory Model](https://go.dev/ref/mem), [Data Race Detector](https://go.dev/doc/articles/race_detector) — goroutine lifetimes, what a race is, what `-race` does not find
- [package time — After](https://pkg.go.dev/time#After) — unreferenced timers are collected since Go 1.23
- [package html/template](https://pkg.go.dev/html/template) — contextual escaping, the typed strings that bypass it, `text/template` does none
- [package encoding/json/v2](https://pkg.go.dev/encoding/json/v2) — duplicate names and invalid UTF-8 rejected by default
- [package uuid](https://pkg.go.dev/uuid) — in the standard library from Go 1.27
- [Effective Go — Defer](https://go.dev/doc/effective_go#defer) — a deferred call runs at function exit
- [Go Code Review Comments](https://go.dev/wiki/CodeReviewComments), [Google Go Style — Decisions](https://google.github.io/styleguide/go/decisions) and [Best practices](https://google.github.io/styleguide/go/best-practices), [Uber Go Style Guide](https://github.com/uber-go/guide/blob/master/style.md) — goroutine lifetimes, interfaces at the consumer, no mutable globals, no `init`
- [Organizing a Go module](https://go.dev/doc/modules/layout) — `cmd/`, `internal/`
- [Security best practices for Go developers](https://go.dev/doc/security/best-practices) — `govulncheck`, the race detector, `go vet`
- [cmd/vet](https://pkg.go.dev/cmd/vet), [gopls analyzers](https://go.dev/gopls/analyzers), [modernize](https://pkg.go.dev/golang.org/x/tools/go/analysis/passes/modernize), [golangci-lint changelog](https://golangci-lint.run/docs/product/changelog/) (v2.15.0), [staticcheck](https://staticcheck.dev/docs/checks/), [gosec](https://github.com/securego/gosec) — the Tooling coverage table
- [Using go fix to modernize Go code](https://go.dev/blog/gofix) — assistants write Go in the style of their training corpus and resist newer idioms; why §8 checks generated code for stale APIs
- [CVE-2025-47909](https://osv.dev/vulnerability/CVE-2025-47909) — gorilla/csrf `TrustedOrigins` bypass, no fixed release; the advisory points to `CrossOriginProtection` or `filippo.io/csrf`
- [OWASP — Authorization](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html), [Mass assignment](https://cheatsheetseries.owasp.org/cheatsheets/Mass_Assignment_Cheat_Sheet.html), [Logging](https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html)

Not confirmed from a primary page, stated in the checklist on practitioner
consensus: the set of linters in golangci-lint's `standard` default
(errcheck, govet, ineffassign, staticcheck, unused); a template executed
straight into the `ResponseWriter` leaves a partial page with status 200. The
Go 1.28 rows come from a draft and can change before the release. No
controlled study of agent-written Go was found; the stale-idiom rules rest on
the Go team's own account.
