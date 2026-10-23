package ui

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestUnconfiguredIoTDoesNotReportSuccess(t *testing.T) {
	hs := &HTTPServer{}
	for name, handler := range map[string]http.HandlerFunc{"relay": hs.handleIOTToggle, "GPS": hs.handleIOTSensorsTrigger, "soil": hs.handleIOTPoll, "schedule": hs.handleIOTSchedule} {
		t.Run(name, func(t *testing.T) {
			w := httptest.NewRecorder()
			handler(w, httptest.NewRequest(http.MethodPost, "/", strings.NewReader(`{}`)))
			if w.Code < 400 {
				t.Fatalf("unconfigured hardware returned success %d: %s", w.Code, w.Body.String())
			}
		})
	}
}
func TestPrintRequiresExplicitPrinterAndValidReceipt(t *testing.T) {
	hs := &HTTPServer{}
	for _, body := range []string{`{}`, `{`, `{"printer_ip":"192.168.1.188","farmer_name":"Farmer","crop_type":"Rice","weight_kg":0,"mandi_rate":0}`} {
		w := httptest.NewRecorder()
		hs.handleIOTPrintGatepass(w, httptest.NewRequest(http.MethodPost, "/", strings.NewReader(body)))
		if w.Code != http.StatusBadRequest {
			t.Fatalf("invalid receipt returned %d", w.Code)
		}
	}
}
