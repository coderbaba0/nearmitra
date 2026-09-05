// Package iot provides AI automation scheduling and timer execution for connected peripherals.
package iot

import (
	"fmt"
	"strconv"
	"strings"
	"sync"
	"time"
)

type AutomationEngine struct {
	mu        sync.RWMutex
	mgr       *Manager
	schedules map[string]*AITaskSchedule
	onEvent   func(string)
	stopChan  chan struct{}
}

// NewAutomationEngine initializes the scheduling and timer controller.
func NewAutomationEngine(mgr *Manager, onEvent func(string)) *AutomationEngine {
	engine := &AutomationEngine{
		mgr:       mgr,
		schedules: make(map[string]*AITaskSchedule),
		onEvent:   onEvent,
		stopChan:  make(chan struct{}),
	}

	// Seed default smart agricultural schedules
	engine.seedDefaultSchedules()

	// Start schedule evaluation loop
	go engine.startSchedulerLoop()

	return engine
}

func (ae *AutomationEngine) seedDefaultSchedules() {
	ae.mu.Lock()
	defer ae.mu.Unlock()

	ae.schedules["sched_pump_morning"] = &AITaskSchedule{
		ID:              "sched_pump_morning",
		DeviceID:        "relay_pump_01",
		DeviceName:      "Kisan Smart Irrigation Pump #1",
		Action:          "turn_on_timer",
		DurationMinutes: 15,
		ScheduledAt:     time.Now().Add(10 * time.Minute),
		AIPromptTrigger: "Auto-irrigate for 15 mins if soil moisture < 35%",
		IsActive:        true,
	}

	ae.schedules["sched_sensor_poll"] = &AITaskSchedule{
		ID:              "sched_sensor_poll",
		DeviceID:        "sensor_soil_01",
		DeviceName:      "Field Sector-A Soil Moisture Sensor",
		Action:          "poll_telemetry",
		DurationMinutes: 0,
		ScheduledAt:     time.Now().Add(5 * time.Minute),
		AIPromptTrigger: "Periodic telemetry sync",
		IsActive:        true,
	}
}

// GetSchedules returns all active or configured automation timers.
func (ae *AutomationEngine) GetSchedules() []AITaskSchedule {
	ae.mu.RLock()
	defer ae.mu.RUnlock()
	list := make([]AITaskSchedule, 0, len(ae.schedules))
	for _, s := range ae.schedules {
		list = append(list, *s)
	}
	return list
}

// AddSchedule registers a new timer or AI-driven schedule.
func (ae *AutomationEngine) AddSchedule(task AITaskSchedule) {
	ae.mu.Lock()
	defer ae.mu.Unlock()
	if task.ID == "" {
		task.ID = fmt.Sprintf("sched_%d", time.Now().UnixNano())
	}
	task.IsActive = true
	ae.schedules[task.ID] = &task
	if ae.onEvent != nil {
		ae.onEvent(fmt.Sprintf("New AI Schedule Added: %s for %s (%d mins)", task.Action, task.DeviceName, task.DurationMinutes))
	}
}

// ToggleSchedule toggles active state of a schedule.
func (ae *AutomationEngine) ToggleSchedule(id string) bool {
	ae.mu.Lock()
	defer ae.mu.Unlock()
	if s, ok := ae.schedules[id]; ok {
		s.IsActive = !s.IsActive
		return s.IsActive
	}
	return false
}

// ParseAIPromptSchedule creates a structured schedule from a natural language prompt.
func (ae *AutomationEngine) ParseAIPromptSchedule(prompt string) (*AITaskSchedule, error) {
	promptLower := strings.ToLower(prompt)

	task := &AITaskSchedule{
		ID:              fmt.Sprintf("ai_sched_%d", time.Now().UnixNano()),
		AIPromptTrigger: prompt,
		IsActive:        true,
	}

	// 1. Identify target device
	if strings.Contains(promptLower, "pump") || strings.Contains(promptLower, "motor") || strings.Contains(promptLower, "water") {
		task.DeviceID = "relay_pump_01"
		task.DeviceName = "Kisan Smart Irrigation Pump #1"
		task.Action = "turn_on_timer"
	} else if strings.Contains(promptLower, "print") || strings.Contains(promptLower, "receipt") || strings.Contains(promptLower, "gate pass") {
		task.DeviceID = "printer_thermal_01"
		task.DeviceName = "Mandi Gate Pass & Receipt Printer"
		task.Action = "test_print"
	} else if strings.Contains(promptLower, "scan") || strings.Contains(promptLower, "document") {
		task.DeviceID = "scanner_doc_01"
		task.DeviceName = "Document & Invoice Scanner"
		task.Action = "scan_document"
	} else {
		task.DeviceID = "sensor_soil_01"
		task.DeviceName = "Field Sector-A Soil Moisture Sensor"
		task.Action = "read_sensor"
	}

	// 2. Parse duration
	duration := 15
	words := strings.Fields(promptLower)
	for i, w := range words {
		if (w == "min" || w == "mins" || w == "minute" || w == "minutes") && i > 0 {
			if num, err := strconv.Atoi(words[i-1]); err == nil && num > 0 {
				duration = num
			}
		}
	}
	task.DurationMinutes = duration
	task.ScheduledAt = time.Now().Add(time.Duration(duration) * time.Minute)

	ae.AddSchedule(*task)
	return task, nil
}

func (ae *AutomationEngine) startSchedulerLoop() {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			now := time.Now()
			ae.mu.Lock()
			for _, s := range ae.schedules {
				if s.IsActive && now.After(s.ScheduledAt) {
					// Execute trigger
					if s.Action == "turn_on_timer" {
						ae.mgr.ToggleRelay(s.DeviceID)
						if ae.onEvent != nil {
							ae.onEvent(fmt.Sprintf("AI Automation Triggered: %s started for %d mins", s.DeviceName, s.DurationMinutes))
						}
					} else if s.Action == "test_print" {
						ae.mgr.TriggerTestPrint(s.DeviceID)
					}
					// Schedule next run
					s.ScheduledAt = now.Add(24 * time.Hour)
				}
			}
			ae.mu.Unlock()

		case <-ae.stopChan:
			return
		}
	}
}

// Close terminates scheduler worker.
func (ae *AutomationEngine) Close() {
	close(ae.stopChan)
}
