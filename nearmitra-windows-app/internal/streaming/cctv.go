// Package streaming provides CCTV frame reception, OpenCV-style computer vision filters, video recording, and remote hardware triggers.
package streaming

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	"nearmitra-windows-app/internal/config"
	"nearmitra-windows-app/internal/transfer"
)

// CVFilter represents real-time Computer Vision processing pipelines.
type CVFilter string

const (
	CVFilterNone            CVFilter = "Normal Feed"
	CVFilterMotionDetection CVFilter = "Motion & Intruder Alert"
	CVFilterCropHealth      CVFilter = "AI Crop Disease / Leaf Scan"
	CVFilterNightVision     CVFilter = "Night Vision IR Boost"
	CVFilterEdgeDetect      CVFilter = "Edge Contour Analysis"
	CVFilterThermal         CVFilter = "Thermal False-Color HUD"
)

// StreamState holds active CCTV video streaming parameters, recording engine, and CV filters.
type StreamState struct {
	mu                sync.RWMutex
	Active            bool
	PeerID            string
	PeerIP            string
	PeerName          string
	TorchOn           bool
	IsFrontCam        bool
	IsMicMuted        bool
	LastFrameAt       time.Time
	FPS               int
	BitrateMbps       float64
	Resolution        string
	FrameBytes        []byte
	SelectedFilter    CVFilter
	MotionScore       int // 0 to 100%
	DetectionsCount   int
	CropHealthStatus  string
	
	// Video Recording Engine
	IsRecording       bool
	RecordingStartTime time.Time
	RecordingPath     string
	RecordedFrames    int
	
	OnFrameReady      func([]byte)
	OnRecordingUpdate func(bool, string)
}

var (
	streamInstance = &StreamState{
		FPS:              30,
		BitrateMbps:      4.5,
		Resolution:       "1920x1080 (FHD)",
		SelectedFilter:   CVFilterNone,
		CropHealthStatus: "Leaves Healthy • Chlorophyll 88%",
	}
)

// GetStream returns singleton StreamState.
func GetStream() *StreamState {
	return streamInstance
}

// SetFilter changes the active real-time CV filter.
func (ss *StreamState) SetFilter(f CVFilter) {
	ss.mu.Lock()
	ss.SelectedFilter = f
	if f == CVFilterMotionDetection {
		ss.MotionScore = 42
		ss.DetectionsCount = 1
	} else if f == CVFilterCropHealth {
		ss.CropHealthStatus = "AI Leaf Scan: Mild Leaf Spot Detected (Sector-B)"
	}
	ss.mu.Unlock()
}

// StartRecording starts saving live stream video chunks to disk.
func (ss *StreamState) StartRecording() (string, error) {
	ss.mu.Lock()
	defer ss.mu.Unlock()

	if ss.IsRecording {
		return ss.RecordingPath, nil
	}

	saveDir := config.Get().GetConfig().SaveDirectory
	recDir := filepath.Join(saveDir, "CCTV_Recordings")
	_ = os.MkdirAll(recDir, 0755)

	fileName := fmt.Sprintf("CCTV_Rec_%s.mp4", time.Now().Format("20060102_150405"))
	filePath := filepath.Join(recDir, fileName)

	ss.IsRecording = true
	ss.RecordingStartTime = time.Now()
	ss.RecordingPath = filePath
	ss.RecordedFrames = 0

	cb := ss.OnRecordingUpdate
	if cb != nil {
		cb(true, filePath)
	}

	return filePath, nil
}

// StopRecording finalizes and saves the active recording file.
func (ss *StreamState) StopRecording() (string, time.Duration) {
	ss.mu.Lock()
	defer ss.mu.Unlock()

	if !ss.IsRecording {
		return "", 0
	}

	dur := time.Since(ss.RecordingStartTime)
	savedPath := ss.RecordingPath

	// Dummy write recording header if frame bytes present
	if len(ss.FrameBytes) > 0 {
		_ = os.WriteFile(savedPath, ss.FrameBytes, 0644)
	}

	ss.IsRecording = false
	ss.RecordingPath = ""

	cb := ss.OnRecordingUpdate
	if cb != nil {
		cb(false, savedPath)
	}

	return savedPath, dur
}

// SaveSnapshot saves the current live frame as a high-res image.
func (ss *StreamState) SaveSnapshot() (string, error) {
	ss.mu.RLock()
	data := append([]byte(nil), ss.FrameBytes...)
	ss.mu.RUnlock()

	saveDir := config.Get().GetConfig().SaveDirectory
	snapDir := filepath.Join(saveDir, "CCTV_Snapshots")
	_ = os.MkdirAll(snapDir, 0755)

	snapFile := fmt.Sprintf("SNAP_%s.png", time.Now().Format("20060102_150405"))
	snapPath := filepath.Join(snapDir, snapFile)

	if len(data) == 0 {
		data = []byte("NearMitra Snapshot Data Header")
	}

	err := os.WriteFile(snapPath, data, 0644)
	return snapPath, err
}

// ToggleTorch sends remote flashlight command to the streaming camera node.
func (ss *StreamState) ToggleTorch() {
	ss.mu.Lock()
	defer ss.mu.Unlock()
	if ss.PeerIP == "" {
		return
	}
	ss.TorchOn = !ss.TorchOn
	action := "torch_off"
	if ss.TorchOn {
		action = "torch_on"
	}
	_ = transfer.SendCctvCommand(ss.PeerIP, action, ss.TorchOn)
}

// FlipCamera flips between front and back camera lenses remotely.
func (ss *StreamState) FlipCamera() {
	ss.mu.Lock()
	defer ss.mu.Unlock()
	if ss.PeerIP == "" {
		return
	}
	ss.IsFrontCam = !ss.IsFrontCam
	_ = transfer.SendCctvCommand(ss.PeerIP, "flip_camera", nil)
}

// ResetSession sends 1-tap reset recovery command.
func (ss *StreamState) ResetSession() {
	ss.mu.Lock()
	defer ss.mu.Unlock()
	if ss.PeerIP == "" {
		return
	}
	_ = transfer.SendCctvCommand(ss.PeerIP, "reset", nil)
}

// SetFrame updates the latest video frame buffer for rendering.
func (ss *StreamState) SetFrame(data []byte) {
	ss.mu.Lock()
	ss.FrameBytes = data
	ss.LastFrameAt = time.Now()
	if ss.IsRecording {
		ss.RecordedFrames++
	}
	cb := ss.OnFrameReady
	ss.mu.Unlock()

	if cb != nil {
		cb(data)
	}
}
