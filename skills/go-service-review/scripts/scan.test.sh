#!/usr/bin/env bash
here=$(cd "$(dirname "$0")" && pwd)
source "$here/../../../scripts/test-lib.sh"
scan="$here/scan.sh"

flags()   { sees "$1" "^## $1" "$out"; }
unflags() { misses "no: $1" "^## $1" "$out"; }

new_repo shop
printf 'module shop\n\ngo 1.27\n' > go.mod
mkdir -p internal/cart internal/order cmd/server

echo "# a handler file"
cat > internal/cart/handler.go <<'GO'
package cart

import (
	"io/ioutil"
	"math/rand"
	"text/template"

	"github.com/pkg/errors"
)

var cache = map[string]Cart{}
var ErrNotFound = errors.New("not found")

func init() {
	rand.Seed(1)
}

func (h *Handler) Show(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-Id")
	cart, err := h.load(context.Background(), userID)
	if err == ErrNotFound {
		http.Error(w, err.Error(), http.StatusNotFound)
	}
	if err != nil {
		http.Error(w, "failed", http.StatusInternalServerError)
		return
	}
	if r.Header.Get("HX-Request") == "true" {
		tmpl := template.Must(template.ParseFiles("cart.html"))
		tmpl.Execute(w, template.HTML(cart.Note))
		return
	}
	http.Redirect(w, r, "/cart", http.StatusSeeOther)
}

func (h *Handler) Add(w http.ResponseWriter, r *http.Request) {
	var in addRequest
	_ = json.NewDecoder(r.Body).Decode(&in)
	rows, err := h.db.Query("SELECT id FROM items WHERE name = '" + in.Name + "'")
	if err != nil {
		return
	}
	for rows.Next() {
		item := item
		defer h.audit(item)
	}
	go h.notify(in)
	slog.Info("added", "token", in.Token)
	slog.Info("token refreshed")
	w.WriteHeader(286)
}

func (h *Handler) load(ctx context.Context, id string) (Cart, error) {
	query := fmt.Sprintf("SELECT * FROM carts WHERE id = %s", id)
	tx, err := h.db.Begin()
	if err != nil {
		return Cart{}, fmt.Errorf("begin: %v", err)
	}
	resp, err := http.Get("https://prices.example/" + id)
	if err != nil {
		log.Fatal(err)
	}
	if pe, ok := err.(*PriceError); ok {
		panic(pe)
	}
	time.Sleep(time.Second)
	var totalPrice float64
	return Cart{}, tx.Commit()
}
GO
out=$(bash "$scan" internal/cart/handler.go)
flags "io/ioutil"
flags "github.com/pkg/errors"
flags "math/rand in a file that handles a secret"
flags "Loop variable copy"
flags "Error discarded with _"
flags "fmt.Errorf with an error argument and no %w"
flags "Error compared with == or !="
flags "Type assertion on an error"
flags "Internal error text sent to the client"
flags "Error response with no return after it"
no_return=$(under 'Error response with no return after it')
sees   "the handler that falls through"         'err\.Error\(\), http\.StatusNotFound' "$no_return"
misses "the one that returns"                   '"failed"' "$no_return"
flags "log.Fatal, os.Exit or panic outside package main"
flags "context.Background\(\) or context.TODO\(\) outside main"
flags "func init\(\)"
flags "Database call with no context"
flags "HTTP request with no context"
flags "time.Sleep"
flags "Request body read with no size limit"
flags "Response body never closed in this function"
flags "SQL built with fmt.Sprintf or \+"
sql=$(under 'SQL built with fmt.Sprintf or +')
sees   "the Sprintf"                            'Sprintf\("SELECT' "$sql"
sees   "the concatenation"                      "name = '\" \+ in.Name" "$sql"
flags "Rows never closed in this function"
flags "Rows iterated with no rows.Err\(\) check"
flags "Transaction begun with no deferred Rollback"
flags "Remote call between Begin and Commit"
flags "Goroutine started"
flags "Package-level mutable variable"
mutable=$(under 'Package-level mutable variable')
sees   "the map"                                'var cache' "$mutable"
misses "a sentinel error is not state"          'ErrNotFound' "$mutable"
flags "defer inside a loop"
flags "text/template"
flags "Escaping bypass"
flags "Template parsed inside a handler"
flags "Template executed straight into the ResponseWriter"
flags "HX-Request decides the response with no Vary header"
flags "http.Redirect in an htmx handler"
flags "Status 286"
flags "Identity read from the request"
flags "SQL in a handler"
flags "Money-looking value as float"
flags "Secret-looking value in a log call"
secrets=$(under 'Secret-looking value in a log call')
sees   "the token argument"                     'in\.Token' "$secrets"
misses "the word in the message is not one"     'token refreshed' "$secrets"
flags "No test in this package"

echo "# a clean service with a test"
cat > internal/order/service.go <<'GO'
package order

var ErrNotFound = errors.New("order: not found")

func (s *Service) Find(ctx context.Context, id uuid.UUID) (Order, error) {
	rows, err := s.db.QueryContext(ctx, "SELECT id, total_cents FROM orders WHERE id = $1", id)
	if err != nil {
		return Order{}, fmt.Errorf("find order %s: %w", id, err)
	}
	defer rows.Close()
	var found []Order
	for rows.Next() {
		var order Order
		if err := rows.Scan(&order.ID, &order.TotalCents); err != nil {
			return Order{}, fmt.Errorf("scan order: %w", err)
		}
		found = append(found, order)
	}
	if err := rows.Err(); err != nil {
		return Order{}, fmt.Errorf("read orders: %w", err)
	}
	if errors.Is(err, sql.ErrNoRows) || len(found) == 0 {
		return Order{}, ErrNotFound
	}
	// time.Sleep(1) was here; a comment is not code
	return found[0], nil
}

func (s *Service) Pay(ctx context.Context, id uuid.UUID) error {
	receipt, err := s.payments.Charge(ctx, id)
	if err != nil {
		return fmt.Errorf("charge %s: %w", id, err)
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin: %w", err)
	}
	defer tx.Rollback()
	for _, line := range receipt.Lines {
		func() {
			defer s.metrics.Observe(line)
			s.record(ctx, tx, line)
		}()
	}
	return tx.Commit()
}
GO
echo 'package order' > internal/order/service_test.go
out=$(bash "$scan" internal/order/service.go)
eq "nothing to flag" "$out" "clean — no mechanical smells"

echo "# main"
cat > cmd/server/main.go <<'GO'
package main

func main() {
	srv := &http.Server{Addr: ":8080", Handler: mux}
	client := &http.Client{}
	if err := srv.ListenAndServe(); err != nil {
		log.Fatal(err)
	}
}
GO
out=$(bash "$scan" cmd/server/main.go)
flags "http.Server with no ReadHeaderTimeout"
flags "http.Client with no Timeout"
flags "Server started with no Shutdown"
unflags "log.Fatal"
unflags "No test"
printf 'package main\n\nfunc main() {\n\tlog.Fatal(http.ListenAndServe(":8080", nil))\n}\n' > cmd/server/main.go
out=$(bash "$scan" cmd/server/main.go)
flags "http.ListenAndServe / http.Serve"

echo "# a test file"
cat > internal/order/service_test.go <<'GO'
package order

func TestFind(t *testing.T) {
	got, err := svc.Find(context.Background(), id)
	if err != nil {
		t.Fatalf("Find: %v", err)
	}
	_ = got
}

func TestPay(t *testing.T) {
	time.Sleep(time.Second)
	svc.Pay(ctx, id)
}

func TestLater(t *testing.T) {
	t.Skip()
}

func helper(t *testing.T) {
	t.Helper()
}
GO
out=$(bash "$scan" internal/order/service_test.go)
flags "Test with no assertion"
bare=$(under 'Test with no assertion')
sees   "the test that asserts nothing"          'TestPay' "$bare"
misses "the test that fails on error"           'TestFind' "$bare"
misses "a helper is not a test"                 'helper' "$bare"
flags "t.Skip with no reason"
flags "time.Sleep in a test"
flags "context.Background\(\) in a test"
unflags "Error discarded"

echo "# an older module, a generated file"
printf 'module shop\n\ngo 1.21\n' > go.mod
out=$(bash "$scan" internal/cart/handler.go)
unflags "Loop variable copy"
printf '// Code generated by templ - DO NOT EDIT.\n\npackage cart\n\nfunc x() { panic("x") }\n' > internal/cart/cart_templ.go
has "a generated file is not scanned"          0 '^generated file' bash "$scan" internal/cart/cart_templ.go

echo "# usage"
has "no argument"                              1 'usage: scan.sh' bash "$scan"
has "a missing file"                           1 'not found: nope.go' bash "$scan" nope.go

finish
