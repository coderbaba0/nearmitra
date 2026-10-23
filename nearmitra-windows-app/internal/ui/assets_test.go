package ui

import (
	"io"
	"net/http"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"
)

func TestInstalledPageScriptsAreServedAsJavaScript(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(serveEmbeddedUI))
	defer server.Close()
	response, err := server.Client().Get(server.URL + "/")
	if err != nil {
		t.Fatal(err)
	}
	html, err := io.ReadAll(response.Body)
	response.Body.Close()
	if err != nil {
		t.Fatal(err)
	}
	scripts := regexp.MustCompile(`<script src="([^"]+)"`).FindAllSubmatch(html, -1)
	if len(scripts) == 0 {
		t.Fatal("no page scripts found")
	}
	wirelessFound := false
	for _, script := range scripts {
		path := string(script[1])
		t.Run(path, func(t *testing.T) {
			res, err := server.Client().Get(server.URL + "/" + path)
			if err != nil {
				t.Fatal(err)
			}
			defer res.Body.Close()
			data, err := io.ReadAll(res.Body)
			if err != nil {
				t.Fatal(err)
			}
			if res.StatusCode != http.StatusOK || !strings.HasPrefix(res.Header.Get("Content-Type"), "application/javascript") || len(data) == 0 {
				t.Fatalf("page script %s unavailable: status=%d content-type=%s bytes=%d", path, res.StatusCode, res.Header.Get("Content-Type"), len(data))
			}
			if path == "wireless-audio.js" && !strings.Contains(string(data), "root.NearMitraWirelessAudio=WirelessAudio") {
				t.Fatal("wrong wireless engine served")
			}
			if !strings.Contains(res.Header.Get("Cache-Control"), "no-store") {
				t.Fatal("stale application scripts may be cached")
			}
		})
		if path == "wireless-audio.js" {
			wirelessFound = true
		}
	}
	if !wirelessFound {
		t.Fatal("wireless audio engine missing from installed page")
	}
}

func TestNativeAudioWorkletDependenciesAreServed(t *testing.T) {
	for _, path := range []string{"/native-audio.js", "/native-audio-worklet.js", "/native-pcm-buffer.js"} {
		response := httptest.NewRecorder()
		serveEmbeddedUI(response, httptest.NewRequest(http.MethodGet, path, nil))
		if response.Code != http.StatusOK || !strings.HasPrefix(response.Header().Get("Content-Type"), "application/javascript") {
			t.Fatalf("native audio module unavailable: %s", path)
		}
	}
}

func TestEmbeddedAssetHandlerDoesNotExposeSourceOrTests(t *testing.T) {
	for _, path := range []string{"/missing.js", "/wireless-audio.test.cjs", "/../server.go", "/api/missing"} {
		response := httptest.NewRecorder()
		serveEmbeddedUI(response, httptest.NewRequest(http.MethodGet, path, nil))
		if response.Code != http.StatusNotFound {
			t.Fatalf("unexpected exposed resource %s", path)
		}
	}
}
