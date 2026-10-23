package wan

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestNoFirebaseEndpointByDefault(t *testing.T) {
	previous := DefaultFirebaseRTDBUrl
	DefaultFirebaseRTDBUrl = ""
	t.Cleanup(func() { DefaultFirebaseRTDBUrl = previous })
	t.Setenv("NEARMITRA_FIREBASE_RTDB_URL", "")
	client := NewFirebaseClient("")
	if client.baseURL != "" || DefaultFirebaseRTDBUrl != "" {
		t.Fatal("unconfigured checkout has a shared Firebase backend")
	}
	service := &WanService{client: client}
	service.Start()
	if service.running || service.config.InternetModeEnabled {
		t.Fatal("WAN started without developer configuration")
	}
}

func TestExplicitFirebaseEndpointAndEmulatorNamespace(t *testing.T) {
	t.Setenv("NEARMITRA_FIREBASE_RTDB_URL", "https://developer-owned.example")
	if NewFirebaseClient("").baseURL != "https://developer-owned.example" {
		t.Fatal("developer environment not used")
	}
	if NewFirebaseClient("https://explicit.example").baseURL != "https://explicit.example" {
		t.Fatal("explicit endpoint not respected")
	}
	client := NewFirebaseClient("http://127.0.0.1:9000/?ns=demo-nearmitra-default-rtdb")
	if got := client.buildURL("sessions/example"); got != "http://127.0.0.1:9000/sessions/example.json?ns=demo-nearmitra-default-rtdb" {
		t.Fatalf("emulator namespace lost: %s", got)
	}
}

func TestConfiguredClientOnlyContactsSelectedDatabase(t *testing.T) {
	var gotPath, gotNamespace string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath, gotNamespace = r.URL.Path, r.URL.Query().Get("ns")
		_, _ = w.Write([]byte(`null`))
	}))
	defer server.Close()
	client := NewFirebaseClient(server.URL + "/?ns=demo-nearmitra-default-rtdb")
	request, err := http.NewRequest(http.MethodGet, client.buildURL("presence/test"), nil)
	if err != nil {
		t.Fatal(err)
	}
	response, err := client.httpClient.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()
	if gotPath != "/presence/test.json" || !strings.HasPrefix(gotNamespace, "demo-") {
		t.Fatalf("wrong database route: %s %s", gotPath, gotNamespace)
	}
}
