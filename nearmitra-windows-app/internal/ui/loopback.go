package ui

// Native render-endpoint capture. No microphone, screen capture or third-party driver.
import (
	"encoding/binary"
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"net/url"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

var loopbackMu sync.Mutex
var audioOle = syscall.NewLazyDLL("ole32.dll")
var audioCoInit = audioOle.NewProc("CoInitializeEx")
var audioCoUninit = audioOle.NewProc("CoUninitialize")
var audioCoCreate = audioOle.NewProc("CoCreateInstance")
var audioCoFree = audioOle.NewProc("CoTaskMemFree")
var audioPropClear = audioOle.NewProc("PropVariantClear")

type audioGUID struct {
	A    uint32
	B, C uint16
	D    [8]byte
}

var audioEnumeratorClass = audioGUID{0xbcde0395, 0xe52f, 0x467c, [8]byte{0x8e, 0x3d, 0xc4, 0x57, 0x92, 0x91, 0x69, 0x2e}}
var audioEnumeratorIID = audioGUID{0xa95664d2, 0x9614, 0x4f35, [8]byte{0xa7, 0x46, 0xde, 0x8d, 0xb6, 0x36, 0x17, 0xe6}}
var audioClientIID = audioGUID{0x1cb9ad4c, 0xdbfa, 0x4c32, [8]byte{0xb1, 0x78, 0xc2, 0xf5, 0x68, 0xa7, 0x03, 0xb2}}
var audioCaptureIID = audioGUID{0xc8adbd64, 0xe71e, 0x48a0, [8]byte{0xa4, 0xde, 0x18, 0x5c, 0x39, 0x5c, 0xd3, 0x17}}

type audioCOM struct{ vtable *[16]uintptr }

func (o *audioCOM) call(method int, args ...uintptr) uintptr {
	r, _, _ := syscall.SyscallN(o.vtable[method], append([]uintptr{uintptr(unsafe.Pointer(o))}, args...)...)
	return r
}
func audioCheck(hr uintptr, operation string) error {
	if int32(uint32(hr)) < 0 {
		return fmt.Errorf("%s failed (Windows audio 0x%08x)", operation, uint32(hr))
	}
	return nil
}
func audioRelease(o *audioCOM) {
	if o != nil {
		o.call(2)
	}
}
func audioString(p uintptr) string {
	if p == 0 {
		return ""
	}
	return syscall.UTF16ToString((*[32768]uint16)(unsafe.Pointer(p))[:])
}
func audioEnumerator() (*audioCOM, error) {
	var o *audioCOM
	hr, _, _ := audioCoCreate.Call(uintptr(unsafe.Pointer(&audioEnumeratorClass)), 0, 1, uintptr(unsafe.Pointer(&audioEnumeratorIID)), uintptr(unsafe.Pointer(&o)))
	return o, audioCheck(hr, "Open Windows playback devices")
}

type renderDevice struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Default bool   `json:"is_default"`
}

func audioDeviceID(o *audioCOM) string {
	var ptr uintptr
	if o.call(5, uintptr(unsafe.Pointer(&ptr))) != 0 {
		return ""
	}
	defer audioCoFree.Call(ptr)
	return audioString(ptr)
}
func audioDeviceName(o *audioCOM) string {
	var store *audioCOM
	if o.call(4, 0, uintptr(unsafe.Pointer(&store))) != 0 {
		return "Windows playback device"
	}
	defer audioRelease(store)
	key := struct {
		ID  audioGUID
		PID uint32
	}{audioGUID{0xa45c254e, 0xdf1c, 0x4efd, [8]byte{0x80, 0x20, 0x67, 0xd1, 0x46, 0xa8, 0x50, 0xe0}}, 14}
	var value [24]byte
	if store.call(5, uintptr(unsafe.Pointer(&key)), uintptr(unsafe.Pointer(&value[0]))) != 0 {
		return "Windows playback device"
	}
	defer audioPropClear.Call(uintptr(unsafe.Pointer(&value[0])))
	if binary.LittleEndian.Uint16(value[:2]) != 31 {
		return "Windows playback device"
	}
	return audioString(uintptr(binary.LittleEndian.Uint64(value[8:16])))
}
func listRenderDevices() ([]renderDevice, error) {
	enum, err := audioEnumerator()
	if err != nil {
		return nil, err
	}
	defer audioRelease(enum)
	var def *audioCOM
	defaultID := ""
	if enum.call(4, 0, 1, uintptr(unsafe.Pointer(&def))) == 0 {
		defaultID = audioDeviceID(def)
		audioRelease(def)
	}
	var collection *audioCOM
	if err = audioCheck(enum.call(3, 0, 1, uintptr(unsafe.Pointer(&collection))), "List active playback devices"); err != nil {
		return nil, err
	}
	defer audioRelease(collection)
	var count uint32
	if err = audioCheck(collection.call(3, uintptr(unsafe.Pointer(&count))), "Read playback devices"); err != nil {
		return nil, err
	}
	devices := []renderDevice{}
	for i := uint32(0); i < count; i++ {
		var device *audioCOM
		if collection.call(4, uintptr(i), uintptr(unsafe.Pointer(&device))) == 0 {
			id := audioDeviceID(device)
			devices = append(devices, renderDevice{id, audioDeviceName(device), id == defaultID})
			audioRelease(device)
		}
	}
	return devices, nil
}

type loopbackFormat struct {
	rate                         uint32
	channels, align, bits, valid uint16
	floating                     bool
}

func parseLoopbackFormat(data []byte) (loopbackFormat, error) {
	if len(data) < 18 {
		return loopbackFormat{}, fmt.Errorf("Truncated Windows audio format")
	}
	tag := binary.LittleEndian.Uint16(data)
	f := loopbackFormat{rate: binary.LittleEndian.Uint32(data[4:8]), channels: binary.LittleEndian.Uint16(data[2:4]), align: binary.LittleEndian.Uint16(data[12:14]), bits: binary.LittleEndian.Uint16(data[14:16])}
	f.valid = f.bits
	if tag == 0xfffe {
		if len(data) < 40 || binary.LittleEndian.Uint16(data[16:18]) < 22 {
			return f, fmt.Errorf("Truncated extended audio format")
		}
		f.valid = binary.LittleEndian.Uint16(data[18:20])
		tag = uint16(binary.LittleEndian.Uint32(data[24:28]))
		// KSDATAFORMAT_SUBTYPE_PCM / IEEE_FLOAT share the canonical GUID suffix.
		expected := []byte{0, 0, 0x10, 0, 0x80, 0, 0, 0xaa, 0, 0x38, 0x9b, 0x71}
		for i, v := range expected {
			if data[28+i] != v {
				return f, fmt.Errorf("Unsupported audio subformat")
			}
		}
	}
	f.floating = tag == 3
	if (tag != 1 && tag != 3) || f.rate < 8000 || f.rate > 384000 || f.channels < 1 || f.channels > 32 || f.bits%8 != 0 || int(f.align) != int(f.channels)*int(f.bits/8) || f.valid > f.bits {
		return f, fmt.Errorf("Unsupported Windows audio format")
	}
	if f.floating && f.bits != 32 && f.bits != 64 {
		return f, fmt.Errorf("Unsupported floating audio format")
	}
	if !f.floating && f.bits != 16 && f.bits != 24 && f.bits != 32 {
		return f, fmt.Errorf("Unsupported PCM bit depth")
	}
	return f, nil
}
func (f loopbackFormat) sample(data []byte) float32 {
	var value float64
	if f.floating {
		if f.bits == 32 {
			value = float64(math.Float32frombits(binary.LittleEndian.Uint32(data)))
		} else {
			value = math.Float64frombits(binary.LittleEndian.Uint64(data))
		}
	} else {
		switch f.bits {
		case 16:
			value = float64(int16(binary.LittleEndian.Uint16(data))) / 32768
		case 24:
			value = float64(int32(uint32(data[0])|uint32(data[1])<<8|uint32(data[2])<<16)<<8) / 2147483648
		case 32:
			value = float64(int32(binary.LittleEndian.Uint32(data))) / 2147483648
		}
	}
	if math.IsNaN(value) || math.IsInf(value, 0) {
		return 0
	}
	return float32(math.Max(-1, math.Min(1, value)))
}
func (f loopbackFormat) encode(data []byte, frames uint32, silent bool) ([]byte, error) {
	if frames > 1<<20 {
		return nil, fmt.Errorf("Windows audio packet is too large")
	}
	if !silent && uint64(len(data)) < uint64(frames)*uint64(f.align) {
		return nil, fmt.Errorf("Truncated Windows audio packet")
	}
	out := make([]byte, int(frames)*8) // stereo float32 little-endian, always interleaved L/R
	if silent {
		return out, nil
	}
	step := int(f.bits / 8)
	for i := 0; i < int(frames); i++ {
		frame := data[i*int(f.align):]
		left := f.sample(frame)
		right := left
		if f.channels > 1 {
			right = f.sample(frame[step:])
		}
		if f.channels > 2 { // Include centre/surround channels while retaining headroom.
			sums := [2]float64{float64(left), float64(right)}
			weights := [2]float64{1, 1}
			for c := 2; c < int(f.channels); c++ {
				v := float64(f.sample(frame[c*step:]))
				if c == 2 {
					sums[0] += v * 0.707
					sums[1] += v * 0.707
					weights[0] += .707
					weights[1] += .707
				} else if c != 3 {
					side := c % 2
					sums[side] += v * .5
					weights[side] += .5
				}
			}
			left = float32(sums[0] / weights[0])
			right = float32(sums[1] / weights[1])
		}
		binary.LittleEndian.PutUint32(out[i*8:], math.Float32bits(left))
		binary.LittleEndian.PutUint32(out[i*8+4:], math.Float32bits(right))
	}
	return out, nil
}

type nativeLoopback struct {
	device, client, capture *audioCOM
	format                  loopbackFormat
	name                    string
	started                 bool
}

func openNativeLoopback(id string) (*nativeLoopback, error) {
	n := &nativeLoopback{}
	success := false
	defer func() {
		if !success {
			n.close()
		}
	}()
	enum, err := audioEnumerator()
	if err != nil {
		return nil, err
	}
	defer audioRelease(enum)
	if id == "" {
		err = audioCheck(enum.call(4, 0, 1, uintptr(unsafe.Pointer(&n.device))), "Select default playback device")
	} else {
		ptr, e := syscall.UTF16PtrFromString(id)
		if e != nil {
			return nil, e
		}
		err = audioCheck(enum.call(5, uintptr(unsafe.Pointer(ptr)), uintptr(unsafe.Pointer(&n.device))), "Select playback device")
	}
	if err != nil {
		return nil, fmt.Errorf("%w. Select or connect a Windows playback output. Without speakers/headphones, a virtual playback device is required for Chrome and desktop players. Browser-tab audio remains available", err)
	}
	n.name = audioDeviceName(n.device)
	if err = audioCheck(n.device.call(3, uintptr(unsafe.Pointer(&audioClientIID)), 23, 0, uintptr(unsafe.Pointer(&n.client))), "Activate system audio capture"); err != nil {
		return nil, err
	}
	var mix uintptr
	if err = audioCheck(n.client.call(8, uintptr(unsafe.Pointer(&mix))), "Read playback sample rate"); err != nil {
		return nil, err
	}
	defer audioCoFree.Call(mix)
	prefix := unsafe.Slice((*byte)(unsafe.Pointer(mix)), 18)
	size := 18 + int(binary.LittleEndian.Uint16(prefix[16:18]))
	if size > 256 {
		return nil, fmt.Errorf("Invalid Windows audio format size")
	}
	n.format, err = parseLoopbackFormat(unsafe.Slice((*byte)(unsafe.Pointer(mix)), size))
	if err != nil {
		return nil, err
	}
	// Shared mode + AUDCLNT_STREAMFLAGS_LOOPBACK. No guessed sample rate.
	if err = audioCheck(n.client.call(3, 0, 0x20000, 1000000, 0, mix, 0), "Start playback loopback"); err != nil {
		return nil, err
	}
	if err = audioCheck(n.client.call(14, uintptr(unsafe.Pointer(&audioCaptureIID)), uintptr(unsafe.Pointer(&n.capture))), "Open loopback packets"); err != nil {
		return nil, err
	}
	if err = audioCheck(n.client.call(10), "Run playback capture"); err != nil {
		return nil, err
	}
	n.started = true
	success = true
	return n, nil
}
func (n *nativeLoopback) close() {
	if n.started {
		n.client.call(11)
	}
	audioRelease(n.capture)
	audioRelease(n.client)
	audioRelease(n.device)
}
func (n *nativeLoopback) packet() ([]byte, error) {
	var next uint32
	if err := audioCheck(n.capture.call(5, uintptr(unsafe.Pointer(&next))), "Read loopback packet size"); err != nil {
		return nil, err
	}
	if next == 0 {
		return nil, nil
	}
	var data uintptr
	var frames, flags uint32
	if err := audioCheck(n.capture.call(3, uintptr(unsafe.Pointer(&data)), uintptr(unsafe.Pointer(&frames)), uintptr(unsafe.Pointer(&flags)), 0, 0), "Read loopback audio"); err != nil {
		return nil, err
	}
	defer n.capture.call(4, uintptr(frames))
	if frames > 1<<20 {
		return nil, fmt.Errorf("Invalid loopback packet size")
	}
	silent := flags&2 != 0
	var bytes []byte
	if !silent {
		if data == 0 {
			return nil, fmt.Errorf("Missing loopback sample buffer")
		}
		bytes = unsafe.Slice((*byte)(unsafe.Pointer(data)), int(frames)*int(n.format.align))
	}
	return n.format.encode(bytes, frames, silent)
}
func withAudioCOM(fn func() error) error {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	hr, _, _ := audioCoInit.Call(0, 0)
	if err := audioCheck(hr, "Initialize Windows audio"); err != nil {
		return err
	}
	defer audioCoUninit.Call()
	return fn()
}
func (hs *HTTPServer) handleAudioDevices(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(405)
		return
	}
	var devices []renderDevice
	err := withAudioCOM(func() error { var err error; devices, err = listRenderDevices(); return err })
	if err != nil {
		http.Error(w, err.Error(), 503)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	json.NewEncoder(w).Encode(map[string]interface{}{"devices": devices})
}
func allowLoopbackRequest(r *http.Request) bool {
	if r.Method != http.MethodPost || r.Header.Get("X-NearMitra-Audio") != "loopback" {
		return false
	}
	if origin := r.Header.Get("Origin"); origin != "" {
		u, err := url.Parse(origin)
		if err != nil || !strings.EqualFold(u.Host, r.Host) {
			return false
		}
	}
	return true
}
func (hs *HTTPServer) handleAudioLoopback(w http.ResponseWriter, r *http.Request) {
	if !allowLoopbackRequest(r) {
		http.Error(w, "Start system audio from NearMitra", 403)
		return
	}
	if !loopbackMu.TryLock() {
		http.Error(w, "System audio is already being captured. Stop the previous wireless audio session", 409)
		return
	}
	defer loopbackMu.Unlock()
	err := withAudioCOM(func() error {
		n, err := openNativeLoopback(r.URL.Query().Get("device"))
		if err != nil {
			return err
		}
		defer n.close()
		w.Header().Set("Content-Type", "application/octet-stream")
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("X-Audio-Sample-Rate", fmt.Sprint(n.format.rate))
		w.Header().Set("X-Audio-Channels", "2")
		w.Header().Set("X-Audio-Device", url.QueryEscape(n.name))
		hs.AddLog(fmt.Sprintf("[AUDIO] Native playback capture: %s, %d Hz, %d input channels", n.name, n.format.rate, n.format.channels))
		w.WriteHeader(200)
		flusher, ok := w.(http.Flusher)
		if !ok {
			return fmt.Errorf("Streaming audio is unavailable")
		}
		flusher.Flush()
		ticker := time.NewTicker(5 * time.Millisecond)
		defer ticker.Stop()
		for {
			select {
			case <-r.Context().Done():
				return nil
			case <-ticker.C:
				for i := 0; i < 32; i++ {
					packet, e := n.packet()
					if e != nil {
						hs.AddLog("[AUDIO] Native capture ended: " + e.Error())
						return nil
					}
					if len(packet) == 0 {
						break
					}
					if _, e = w.Write(packet); e != nil {
						return nil
					}
					flusher.Flush()
				}
			}
		}
	})
	if err != nil {
		hs.AddLog("[AUDIO] Native capture failed: " + err.Error())
		http.Error(w, err.Error(), 503)
	}
}
