package ui

import (
	"encoding/binary"
	"math"
	"net/http/httptest"
	"os"
	"runtime"
	"syscall"
	"testing"
	"time"
	"unsafe"
)

func testWaveFormat(tag, bits, channels uint16, rate uint32) []byte {
	b := make([]byte, 18)
	binary.LittleEndian.PutUint16(b, tag)
	binary.LittleEndian.PutUint16(b[2:], channels)
	binary.LittleEndian.PutUint32(b[4:], rate)
	binary.LittleEndian.PutUint16(b[12:], channels*bits/8)
	binary.LittleEndian.PutUint16(b[14:], bits)
	return b
}
func TestNativePCMFormatAndConversion(t *testing.T) {
	for _, bits := range []uint16{16, 24, 32} {
		f, err := parseLoopbackFormat(testWaveFormat(1, bits, 1, 44100))
		if err != nil {
			t.Fatal(err)
		}
		sample := make([]byte, bits/8)
		sample[len(sample)-1] = 0x40 // exactly +0.5 at any supported PCM depth
		out, err := f.encode(sample, 1, false)
		if err != nil {
			t.Fatal(err)
		}
		if f.rate != 44100 || len(out) != 8 || math.Float32frombits(binary.LittleEndian.Uint32(out)) != 0.5 || binary.LittleEndian.Uint32(out) != binary.LittleEndian.Uint32(out[4:]) {
			t.Fatalf("wrong %d-bit mono PCM conversion: %v", bits, out)
		}
	}
	f, _ := parseLoopbackFormat(testWaveFormat(3, 32, 2, 48000))
	packet := make([]byte, 8)
	binary.LittleEndian.PutUint32(packet, math.Float32bits(-.25))
	binary.LittleEndian.PutUint32(packet[4:], math.Float32bits(.75))
	out, err := f.encode(packet, 1, false)
	if err != nil || math.Float32frombits(binary.LittleEndian.Uint32(out)) != -.25 || math.Float32frombits(binary.LittleEndian.Uint32(out[4:])) != .75 {
		t.Fatalf("float stereo changed: %v %v", out, err)
	}
	silent, err := f.encode(nil, 10, true)
	if err != nil || len(silent) != 80 {
		t.Fatal("silent flags not honoured")
	}
	for _, v := range silent {
		if v != 0 {
			t.Fatal("silent packet contains noise")
		}
	}
	if _, err = f.encode(nil, 10, false); err == nil {
		t.Fatal("truncated packet accepted")
	}
	for _, bad := range [][]byte{nil, testWaveFormat(99, 32, 2, 48000), testWaveFormat(1, 16, 0, 48000), testWaveFormat(3, 16, 2, 48000)} {
		if _, err := parseLoopbackFormat(bad); err == nil {
			t.Fatal("invalid format accepted")
		}
	}
}
func TestLoopbackCaptureRequiresExplicitSameOriginAction(t *testing.T) {
	for _, item := range []struct {
		method, origin, header string
		want                   bool
	}{
		{"GET", "", "loopback", false}, {"POST", "", "", false}, {"POST", "https://outside.example", "loopback", false}, {"POST", "http://127.0.0.1:43880", "loopback", true}, {"POST", "", "loopback", true},
	} {
		r := httptest.NewRequest(item.method, "http://127.0.0.1:43880/api/audio/loopback", nil)
		r.Header.Set("Origin", item.origin)
		r.Header.Set("X-NearMitra-Audio", item.header)
		if allowLoopbackRequest(r) != item.want {
			t.Fatalf("incorrect capture permission: %+v", item)
		}
	}
}
func TestNativeLoopbackToneOnCurrentWindowsDevice(t *testing.T) {
	if os.Getenv("NEARMITRA_AUDIO_HARDWARE_TEST") != "1" {
		t.Skip("explicit real-device diagnostic only")
	}
	err := withAudioCOM(func() error {
		devices, err := listRenderDevices()
		if err != nil {
			return err
		}
		t.Logf("active render devices: %+v", devices)
		if len(devices) == 0 {
			t.Skip("No active Windows playback endpoint; native tone capture requires a physical or virtual output")
		}
		capture, err := openNativeLoopback("")
		if err != nil {
			return err
		}
		defer capture.close()
		// A short known 440-Hz tone verifies actual desktop rendering -> native PCM.
		rate := 48000
		frames := rate / 3
		wav := make([]byte, 44+frames*2)
		copy(wav, "RIFF")
		binary.LittleEndian.PutUint32(wav[4:], uint32(len(wav)-8))
		copy(wav[8:], "WAVEfmt ")
		binary.LittleEndian.PutUint32(wav[16:], 16)
		binary.LittleEndian.PutUint16(wav[20:], 1)
		binary.LittleEndian.PutUint16(wav[22:], 1)
		binary.LittleEndian.PutUint32(wav[24:], uint32(rate))
		binary.LittleEndian.PutUint32(wav[28:], uint32(rate*2))
		binary.LittleEndian.PutUint16(wav[32:], 2)
		binary.LittleEndian.PutUint16(wav[34:], 16)
		copy(wav[36:], "data")
		binary.LittleEndian.PutUint32(wav[40:], uint32(frames*2))
		for i := 0; i < frames; i++ {
			binary.LittleEndian.PutUint16(wav[44+i*2:], uint16(int16(math.Sin(float64(i)*2*math.Pi*440/float64(rate))*3200)))
		}
		played := make(chan uintptr, 1)
		go func() {
			r, _, _ := syscall.NewLazyDLL("winmm.dll").NewProc("PlaySoundW").Call(uintptr(unsafe.Pointer(&wav[0])), 0, 6)
			runtime.KeepAlive(wav)
			played <- r
		}()
		deadline := time.Now().Add(2 * time.Second)
		peak := float32(0)
		samples := 0
		for time.Now().Before(deadline) {
			packet, e := capture.packet()
			if e != nil {
				return e
			}
			for i := 0; i < len(packet); i += 4 {
				v := math.Float32frombits(binary.LittleEndian.Uint32(packet[i:]))
				if v < 0 {
					v = -v
				}
				if v > peak {
					peak = v
				}
				samples++
			}
			time.Sleep(5 * time.Millisecond)
		}
		if <-played == 0 {
			t.Error("Windows could not render test tone")
		}
		t.Logf("captured native output: %s, %d Hz, %d channels, samples=%d, peak=%f", capture.name, capture.format.rate, capture.format.channels, samples, peak)
		if peak < 0.005 {
			t.Error("Rendered tone was not captured as real system audio")
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
}
