package transfer

import (
	"archive/zip"
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"time"

	"nearmitra-windows-app/internal/config"
	"nearmitra-windows-app/internal/models"
	"nearmitra-windows-app/internal/network"
)

// SendTextMessage transmits chat text over TCP port 43889 to peer.
func SendTextMessage(targetIP string, msgID string, text string) error {
	cfg := config.Get().GetConfig()
	header := models.WireHeader{
		Type:        "chat",
		Sender:      cfg.DeviceName,
		SenderID:    cfg.DeviceID,
		Message:     text,
		Text:        text,
		TargetMsgID: msgID,
		MsgID:       msgID,
	}
	return sendJSONHeaderOnly(targetIP, header)
}

// SendReaction transmits emoji reaction (👍, ❤️, 👎, 🤔, 😂) to peer.
func SendReaction(targetIP string, targetMsgID string, emoji string) error {
	cfg := config.Get().GetConfig()
	header := models.WireHeader{
		Type:        "reaction",
		Sender:      cfg.DeviceName,
		SenderID:    cfg.DeviceID,
		Reaction:    emoji,
		TargetMsgID: targetMsgID,
		MsgID:       targetMsgID,
	}
	return sendJSONHeaderOnly(targetIP, header)
}

// SendTypingStatus notifies peer whether user is typing.
func SendTypingStatus(targetIP string, isTyping bool) error {
	cfg := config.Get().GetConfig()
	val := "false"
	if isTyping {
		val = "true"
	}
	header := models.WireHeader{
		Type:     "typing",
		Sender:   cfg.DeviceName,
		SenderID: cfg.DeviceID,
		IsTyping: isTyping,
		Message:  val,
	}
	return sendJSONHeaderOnly(targetIP, header)
}

// SendWebRTCSignal sends WebRTC stream negotiation payloads (stream_offer, stream_answer, stream_ice, stream_control) over TCP 43889.
func SendWebRTCSignal(targetIP string, payload map[string]interface{}) error {
	cfg := config.Get().GetConfig()
	payload["sender"] = cfg.DeviceName
	payload["sender_id"] = cfg.DeviceID
	payload["name"] = cfg.DeviceName
	payload["id"] = cfg.DeviceID

	conn, err := net.DialTimeout("tcp", fmt.Sprintf("%s:%d", targetIP, models.TransferPort), 4*time.Second)
	if err != nil {
		return err
	}
	defer conn.Close()

	if host, _, splitErr := net.SplitHostPort(conn.LocalAddr().String()); splitErr == nil {
		payload["sender_ip"] = host
	}

	data, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	_, err = conn.Write(append(data, '\n'))
	return err
}

// SendCctvCommand sends remote camera control actions (torch, flip, mute) in Flutter StreamHub & NearMitra format.
func SendCctvCommand(targetIP string, action string, value interface{}) error {
	cfg := config.Get().GetConfig()

	// Normalize action for Flutter StreamHub
	flutterAction := action
	var boolVal interface{} = value

	if action == "torch_on" {
		flutterAction = "toggle_torch"
		boolVal = true
	} else if action == "torch_off" {
		flutterAction = "toggle_torch"
		boolVal = false
	} else if action == "flip_camera" || action == "flip" {
		flutterAction = "switch_camera"
	} else if action == "mute_mic" {
		flutterAction = "toggle_mic"
		boolVal = true
	} else if action == "unmute_mic" {
		flutterAction = "toggle_mic"
		boolVal = false
	}

	payload := map[string]interface{}{
		"type":        "stream_control",
		"sender":      cfg.DeviceName,
		"sender_id":   cfg.DeviceID,
		"action":      flutterAction,
		"cctv_action": action,
	}
	if boolVal != nil {
		payload["value"] = boolVal
	}

	return SendWebRTCSignal(targetIP, payload)
}

// SendFile streams a local file to remote peer with live progress updates.
func SendFile(targetIP string, filePath string, onProgress func(models.TransferProgress)) error {
	file, err := os.Open(filePath)
	if err != nil {
		return err
	}
	defer file.Close()

	stat, err := file.Stat()
	if err != nil {
		return err
	}

	cfg := config.Get().GetConfig()
	conn, err := net.DialTimeout("tcp", fmt.Sprintf("%s:%d", targetIP, models.TransferPort), 4*time.Second)
	if err != nil {
		return err
	}
	defer conn.Close()

	header := models.WireHeader{
		Type:     "file",
		Sender:   cfg.DeviceName,
		SenderID: cfg.DeviceID,
		Name:     filepath.Base(filePath),
		Size:     stat.Size(),
	}

	configureDelivery(&header, targetIP)
	hData, err := json.Marshal(header)
	if err != nil {
		return err
	}

	// Write header line followed by newline
	if _, err := conn.Write(append(hData, '\n')); err != nil {
		return err
	}

	buf := make([]byte, 64*1024)
	var sent int64
	startTime := time.Now()

	for {
		n, rErr := file.Read(buf)
		if n > 0 {
			if _, wErr := conn.Write(buf[:n]); wErr != nil {
				return wErr
			}
			sent += int64(n)

			if onProgress != nil {
				elapsed := time.Since(startTime).Seconds()
				var speed float64
				if elapsed > 0.1 {
					speed = (float64(sent) / (1024 * 1024)) / elapsed
				}
				onProgress(models.TransferProgress{
					Active:     true,
					Direction:  "upload",
					FileName:   header.Name,
					BytesTotal: stat.Size(),
					BytesSent:  sent,
					SpeedMBps:  speed,
					StartTime:  startTime,
				})
			}
		}
		if rErr != nil {
			if rErr == io.EOF {
				break
			}
			return rErr
		}
	}

	if err := awaitDelivery(conn, header); err != nil {
		return err
	}
	if onProgress != nil {
		onProgress(models.TransferProgress{
			Active:     false,
			Direction:  "upload",
			FileName:   header.Name,
			BytesTotal: stat.Size(),
			BytesSent:  sent,
			Complete:   true,
		})
	}
	return nil
}

// SendFolder archives a folder to temporary zip and streams it.
func SendFolder(targetIP string, folderPath string, onProgress func(models.TransferProgress)) error {
	tempZip := filepath.Join(os.TempDir(), filepath.Base(folderPath)+".zip")
	defer os.Remove(tempZip)

	if err := zipFolder(folderPath, tempZip); err != nil {
		return err
	}

	file, err := os.Open(tempZip)
	if err != nil {
		return err
	}
	defer file.Close()

	stat, err := file.Stat()
	if err != nil {
		return err
	}

	cfg := config.Get().GetConfig()
	conn, err := net.DialTimeout("tcp", fmt.Sprintf("%s:%d", targetIP, models.TransferPort), 4*time.Second)
	if err != nil {
		return err
	}
	defer conn.Close()

	header := models.WireHeader{
		Type:     "file",
		Sender:   cfg.DeviceName,
		SenderID: cfg.DeviceID,
		Name:     filepath.Base(folderPath) + ".zip",
		Size:     stat.Size(),
		Folder:   true,
	}

	configureDelivery(&header, targetIP)
	hData, err := json.Marshal(header)
	if err != nil {
		return err
	}

	if _, err := conn.Write(append(hData, '\n')); err != nil {
		return err
	}

	buf := make([]byte, 64*1024)
	var sent int64
	startTime := time.Now()

	for {
		n, rErr := file.Read(buf)
		if n > 0 {
			if _, wErr := conn.Write(buf[:n]); wErr != nil {
				return wErr
			}
			sent += int64(n)

			if onProgress != nil {
				elapsed := time.Since(startTime).Seconds()
				var speed float64
				if elapsed > 0.1 {
					speed = (float64(sent) / (1024 * 1024)) / elapsed
				}
				onProgress(models.TransferProgress{
					Active:     true,
					Direction:  "upload",
					FileName:   filepath.Base(folderPath),
					BytesTotal: stat.Size(),
					BytesSent:  sent,
					SpeedMBps:  speed,
					StartTime:  startTime,
				})
			}
		}
		if rErr != nil {
			if rErr == io.EOF {
				break
			}
			return rErr
		}
	}

	if err := awaitDelivery(conn, header); err != nil {
		return err
	}
	if onProgress != nil {
		onProgress(models.TransferProgress{
			Active:     false,
			Direction:  "upload",
			FileName:   filepath.Base(folderPath),
			BytesTotal: stat.Size(),
			BytesSent:  sent,
			Complete:   true,
		})
	}
	return nil
}

func sendJSONHeaderOnly(targetIP string, header models.WireHeader) error {
	conn, err := net.DialTimeout("tcp", fmt.Sprintf("%s:%d", targetIP, models.TransferPort), 3*time.Second)
	if err != nil {
		return err
	}
	defer conn.Close()

	configureDelivery(&header, targetIP)
	data, err := json.Marshal(header)
	if err != nil {
		return err
	}
	_, err = conn.Write(append(data, '\n'))
	if err != nil {
		return err
	}
	return awaitDelivery(conn, header)
}

func zipFolder(src, destZip string) error {
	outFile, err := os.Create(destZip)
	if err != nil {
		return err
	}
	defer outFile.Close()

	w := zip.NewWriter(outFile)
	defer w.Close()

	return filepath.Walk(src, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		relPath, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}
		if relPath == "." {
			return nil
		}
		if info.IsDir() {
			_, err = w.Create(filepath.ToSlash(relPath) + "/")
			return err
		}
		header, err := zip.FileInfoHeader(info)
		if err != nil {
			return err
		}
		header.Name = filepath.ToSlash(relPath)
		header.Method = zip.Deflate

		writer, err := w.CreateHeader(header)
		if err != nil {
			return err
		}
		file, err := os.Open(path)
		if err != nil {
			return err
		}
		defer file.Close()
		_, err = io.Copy(writer, file)
		return err
	})
}

func configureDelivery(header *models.WireHeader, ip string) {
	header.InternetDeviceID = config.Get().GetConfig().DeviceID
	header.SupportsDeliveryAck = true
	if header.Type != "chat" && header.Type != "file" {
		return
	}
	for _, peer := range network.GetDiscovery().GetPeers() {
		if peer.IP == ip {
			header.RequireAck = peer.SupportsDeliveryAck
			break
		}
	}
}
func awaitDelivery(conn net.Conn, header models.WireHeader) error {
	if !header.RequireAck {
		return nil
	}
	_ = conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	var reply models.WireHeader
	if err := json.NewDecoder(bufio.NewReader(conn)).Decode(&reply); err != nil {
		return fmt.Errorf("receiver did not confirm delivery: %w", err)
	}
	if reply.Type != "delivery_ack" || reply.Status != "delivered" {
		return fmt.Errorf("receiver could not save transfer: %s", reply.Error)
	}
	return nil
}

// ArchiveFolder prepares a directory for a WAN transfer using the same LAN archive format.
func ArchiveFolder(source, destination string) error { return zipFolder(source, destination) }
