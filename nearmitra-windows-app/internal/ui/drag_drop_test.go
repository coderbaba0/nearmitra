package ui

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestDroppedFileEndpointRegisteredAndRejectsUnavailableTarget(t *testing.T) {
	// Exercise actual application routes: the unregistered upload used to 404.
	hs := &HTTPServer{}
	for _, tc := range []struct {
		method, path string
		code         int
	}{
		{http.MethodGet, "/api/send-file-upload", http.StatusMethodNotAllowed},
		{http.MethodPost, "/api/send-file-upload", http.StatusBadRequest},
	} {
		w := httptest.NewRecorder()
		hs.routes().ServeHTTP(w, httptest.NewRequest(tc.method, tc.path, strings.NewReader("not an upload")))
		if w.Code != tc.code {
			t.Fatalf("%s: got %d (%s), want %d", tc.method, w.Code, w.Body.String(), tc.code)
		}
		if tc.method == http.MethodPost && !strings.Contains(w.Body.String(), "offline") {
			t.Fatal("missing offline explanation")
		}
	}
}
