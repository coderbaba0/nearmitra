package iot

import (
	"encoding/hex"
	"fmt"
	"strings"
	"sync"
	"syscall"
	"unsafe"
)

var nfcReadMu sync.Mutex

// ReadLocalNFCTag reads the UID from PC/SC contactless readers supporting GET DATA.
// It does not claim to decode arbitrary NDEF or MIFARE application data.
func ReadLocalNFCTag() (map[string]interface{}, error) {
	if !nfcReadMu.TryLock() {
		return nil, fmt.Errorf("NFC reader is busy; wait for the previous request")
	}
	defer nfcReadMu.Unlock()
	dll := syscall.NewLazyDLL("winscard.dll")
	establish := dll.NewProc("SCardEstablishContext")
	release := dll.NewProc("SCardReleaseContext")
	list := dll.NewProc("SCardListReadersW")
	connect := dll.NewProc("SCardConnectW")
	disconnect := dll.NewProc("SCardDisconnect")
	transmit := dll.NewProc("SCardTransmit")
	var context uintptr
	code, _, _ := establish.Call(0, 0, 0, uintptr(unsafe.Pointer(&context)))
	if code != 0 {
		return nil, fmt.Errorf("Windows Smart Card service unavailable (0x%X)", uint32(code))
	}
	defer release.Call(context)
	var size uint32
	code, _, _ = list.Call(context, 0, 0, uintptr(unsafe.Pointer(&size)))
	if code != 0 || size < 2 || size > 65536 {
		return nil, fmt.Errorf("no PC/SC reader detected; connect a supported USB NFC reader")
	}
	readers := make([]uint16, size)
	code, _, _ = list.Call(context, 0, uintptr(unsafe.Pointer(&readers[0])), uintptr(unsafe.Pointer(&size)))
	if code != 0 {
		return nil, fmt.Errorf("could not list PC/SC readers (0x%X)", uint32(code))
	}
	for offset := 0; offset < len(readers) && readers[offset] != 0; {
		end := offset
		for end < len(readers) && readers[end] != 0 {
			end++
		}
		name := syscall.UTF16ToString(readers[offset:end])
		offset = end + 1
		namePtr, _ := syscall.UTF16PtrFromString(name)
		var card uintptr
		var protocol uint32
		code, _, _ = connect.Call(context, uintptr(unsafe.Pointer(namePtr)), 2, 3, uintptr(unsafe.Pointer(&card)), uintptr(unsafe.Pointer(&protocol)))
		if code != 0 {
			continue
		}
		request := struct {
			Protocol uint32
			Length   uint32
		}{protocol, 8}
		command := []byte{0xff, 0xca, 0, 0, 0}
		response := make([]byte, 258)
		length := uint32(len(response))
		code, _, _ = transmit.Call(card, uintptr(unsafe.Pointer(&request)), uintptr(unsafe.Pointer(&command[0])), uintptr(len(command)), 0, uintptr(unsafe.Pointer(&response[0])), uintptr(unsafe.Pointer(&length)))
		disconnect.Call(card, 0)
		if code != 0 || length < 3 || length > uint32(len(response)) {
			continue
		}
		if response[length-2] != 0x90 || response[length-1] != 0 {
			continue
		}
		return map[string]interface{}{"tag_id": strings.ToUpper(hex.EncodeToString(response[:length-2])), "tag_type": "PC/SC contactless UID", "reader": name, "ndef_data": "UID read successfully. Application/NDEF decoding is not enabled."}, nil
	}
	return nil, fmt.Errorf("no readable contactless tag; place a tag on a PC/SC reader supporting GET DATA UID")
}
