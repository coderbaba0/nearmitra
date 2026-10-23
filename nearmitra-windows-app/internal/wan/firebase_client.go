package wan

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

const (
	DefaultFirebaseRTDBUrl = "" // No shared production backend.
)

// FirebaseClient handles lightweight REST interactions with Firebase Realtime Database.
type FirebaseClient struct {
	baseURL    string
	httpClient *http.Client
}

// NewFirebaseClient creates a new client with the provided RTDB base URL.
func NewFirebaseClient(baseURL string) *FirebaseClient {
	if baseURL == "" {
		baseURL = strings.TrimSpace(os.Getenv("NEARMITRA_FIREBASE_RTDB_URL"))
	}
	baseURL = strings.TrimSuffix(baseURL, "/")

	return &FirebaseClient{
		baseURL: baseURL,
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

// buildURL constructs the .json endpoint for Firebase REST API.
func (fc *FirebaseClient) buildURL(path string) string {
	path = strings.TrimPrefix(path, "/")
	endpoint, err := url.Parse(fc.baseURL)
	if err != nil {
		return "" // Request construction fails without issuing a network call.
	}
	endpoint.Path = strings.TrimSuffix(endpoint.Path, "/") + "/" + path + ".json"
	return endpoint.String()
}

// Get performs a GET request and deserializes the JSON response into v.
func (fc *FirebaseClient) Get(ctx context.Context, path string, v interface{}) error {
	reqURL := fc.buildURL(path)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, reqURL, nil)
	if err != nil {
		return err
	}

	resp, err := fc.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return fmt.Errorf("node not found: %s", path)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		b, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("firebase GET error %d: %s", resp.StatusCode, string(b))
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}

	if string(body) == "null" {
		return nil
	}

	return json.Unmarshal(body, v)
}

// Put replaces the data at path with the given value.
func (fc *FirebaseClient) Put(ctx context.Context, path string, v interface{}) error {
	reqURL := fc.buildURL(path)
	data, err := json.Marshal(v)
	if err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPut, reqURL, bytes.NewReader(data))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := fc.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		b, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("firebase PUT error %d: %s", resp.StatusCode, string(b))
	}
	return nil
}

// Patch updates specific keys at path without overwriting other child nodes.
func (fc *FirebaseClient) Patch(ctx context.Context, path string, v interface{}) error {
	reqURL := fc.buildURL(path)
	data, err := json.Marshal(v)
	if err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPatch, reqURL, bytes.NewReader(data))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := fc.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		b, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("firebase PATCH error %d: %s", resp.StatusCode, string(b))
	}
	return nil
}

// Delete removes the data at path.
func (fc *FirebaseClient) Delete(ctx context.Context, path string) error {
	reqURL := fc.buildURL(path)
	req, err := http.NewRequestWithContext(ctx, http.MethodDelete, reqURL, nil)
	if err != nil {
		return err
	}

	resp, err := fc.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		b, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("firebase DELETE error %d: %s", resp.StatusCode, string(b))
	}
	return nil
}

// CheckConnectivity verifies if Firebase RTDB is accessible.
func (fc *FirebaseClient) CheckConnectivity(ctx context.Context) bool {
	reqURL := fc.buildURL(".info/connected")
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, reqURL, nil)
	if err != nil {
		return false
	}

	client := &http.Client{Timeout: 4 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()

	return resp.StatusCode >= 200 && resp.StatusCode < 300
}
