package iot

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"time"
)

type RelaySchedule struct {
	ID              string    `json:"id"`
	Endpoint        string    `json:"endpoint"`
	Channel         int       `json:"channel"`
	At              time.Time `json:"at"`
	DurationSeconds int       `json:"duration_seconds"`
	Power           bool      `json:"power"`
	Status          string    `json:"status"`
	Error           string    `json:"error,omitempty"`
}

var scheduleState = struct {
	sync.Mutex
	Path  string
	Items []RelaySchedule
}{}

func LoadRelaySchedules(path string) error {
	scheduleState.Lock()
	defer scheduleState.Unlock()
	scheduleState.Path = path
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	return json.Unmarshal(data, &scheduleState.Items)
}
func persistSchedules() error {
	if scheduleState.Path == "" {
		return fmt.Errorf("schedule storage unavailable")
	}
	data, err := json.MarshalIndent(scheduleState.Items, "", "  ")
	if err != nil {
		return err
	}
	if err = os.MkdirAll(filepath.Dir(scheduleState.Path), 0700); err != nil {
		return err
	}
	tmp := scheduleState.Path + ".tmp"
	if err = os.WriteFile(tmp, data, 0600); err != nil {
		return err
	}
	return os.Rename(tmp, scheduleState.Path)
}
func GetRelaySchedules() []RelaySchedule {
	scheduleState.Lock()
	defer scheduleState.Unlock()
	return append([]RelaySchedule{}, scheduleState.Items...)
}
func AddRelaySchedule(s RelaySchedule) error {
	if s.Channel < 1 || s.Channel > 4 || GetGatewayConfig().Relays[s.Channel-1] == "" {
		return fmt.Errorf("configure a relay channel first")
	}
	if !s.At.After(time.Now()) || s.At.After(time.Now().Add(365*24*time.Hour)) || s.DurationSeconds < 1 || s.DurationSeconds > 86400 {
		return fmt.Errorf("choose a future time within one year and duration of 1–86400 seconds")
	}
	s.Endpoint = GetGatewayConfig().Relays[s.Channel-1]
	s.ID = strconv.FormatInt(time.Now().UnixNano(), 10)
	s.Status = "pending"
	s.Power = true
	s.Error = ""
	// Persist the OFF operation before any ON request can run, including after restart.
	off := RelaySchedule{ID: s.ID + "_off", Endpoint: s.Endpoint, Channel: s.Channel, At: s.At.Add(time.Duration(s.DurationSeconds) * time.Second), Power: false, Status: "pending"}
	scheduleState.Lock()
	defer scheduleState.Unlock()
	pendingOff := map[string]bool{}
	for _, entry := range scheduleState.Items {
		if !entry.Power && entry.Status == "pending" {
			pendingOff[entry.ID] = true
		}
	}
	for _, existing := range scheduleState.Items {
		if existing.Power && existing.Endpoint == s.Endpoint && pendingOff[existing.ID+"_off"] && existing.Status != "cancelled" && existing.Status != "skipped" && s.At.Before(existing.At.Add(time.Duration(existing.DurationSeconds)*time.Second)) && existing.At.Before(off.At) {
			return fmt.Errorf("this relay already has an overlapping timer")
		}
	}
	old := scheduleState.Items
	scheduleState.Items = append(append([]RelaySchedule{}, old...), s, off)
	if err := persistSchedules(); err != nil {
		scheduleState.Items = old
		return err
	}
	return nil
}
func RunRelaySchedules(now time.Time) {
	scheduleState.Lock()
	defer scheduleState.Unlock()
	dirty := false
	for i := range scheduleState.Items {
		s := &scheduleState.Items[i]
		if s.Status != "pending" || now.Before(s.At) {
			continue
		}
		dirty = true
		if s.Power && (now.Sub(s.At) > time.Minute || !now.Before(s.At.Add(time.Duration(s.DurationSeconds)*time.Second))) {
			s.Status = "skipped"
			s.Error = "Start time passed while app was closed"
			continue
		}
		relayOperations.Lock()
		_, err := setRelayEndpoint(context.Background(), s.Endpoint, s.Power)
		relayOperations.Unlock()
		if err != nil {
			s.Error = err.Error()
			if s.Power {
				s.Status = "failed"
			} else {
				s.At = now.Add(10 * time.Second)
			}
		} else {
			s.Status = "completed"
			s.Error = ""
		}
	}
	if dirty {
		_ = persistSchedules()
	}
}

// CancelRelaySchedule cancels a timer pair. If its ON was acknowledged, OFF must
// be acknowledged before the recovery operation can be removed.
func CancelRelaySchedule(id string) error {
	scheduleState.Lock()
	defer scheduleState.Unlock()
	index := -1
	for i, s := range scheduleState.Items {
		if s.ID == id && s.Power {
			index = i
			break
		}
	}
	if index < 0 {
		return fmt.Errorf("timer not found")
	}
	start := scheduleState.Items[index]
	if start.Status == "completed" || start.Status == "failed" {
		relayOperations.Lock()
		_, err := setRelayEndpoint(context.Background(), start.Endpoint, false)
		relayOperations.Unlock()
		if err != nil {
			return fmt.Errorf("could not confirm OFF; recovery timer retained: %w", err)
		}
	}
	for i := range scheduleState.Items {
		if scheduleState.Items[i].ID == id || scheduleState.Items[i].ID == id+"_off" {
			scheduleState.Items[i].Status = "cancelled"
		}
	}
	return persistSchedules()
}
