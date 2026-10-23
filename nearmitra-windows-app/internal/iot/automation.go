// Package iot provides AI automation scheduling and timer execution for connected peripherals.
package iot

import (
	"fmt"
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
	// Schedules are created only when explicitly configured.

	// Start schedule evaluation loop
	go engine.startSchedulerLoop()

	return engine
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
	return nil, fmt.Errorf("use the IoT relay timer to select a configured channel, start time and duration")
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
						_, err := ae.mgr.ToggleRelay(s.DeviceID)
						if ae.onEvent != nil && err != nil {
							ae.onEvent("Automation failed: " + err.Error())
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
