// Package iot provides virtual hardware bridging (Audio Cast, Remote Mic, Virtual Cam, ESC/POS printing, and NFC).
package iot

import (
	"fmt"
	"net"
	"time"
)

// GenerateSampleGatePassReceipt creates a standardized ESC/POS receipt for thermal printers.
func GenerateSampleGatePassReceipt(farmerName string, cropType string, weightKg float64, mandiRate float64) []byte {
	var buf []byte
	// ESC @ (Initialize Printer)
	buf = append(buf, 0x1B, 0x40)
	// ESC a 1 (Center Align)
	buf = append(buf, 0x1B, 0x61, 0x01)
	// Bold ON
	buf = append(buf, 0x1B, 0x45, 0x01)
	buf = append(buf, []byte("================================\n")...)
	buf = append(buf, []byte("      NEARMITRA KRISHI MANDI    \n")...)
	buf = append(buf, []byte("     GATE PASS & DISPATCH SLIP  \n")...)
	buf = append(buf, []byte("================================\n")...)
	// Bold OFF
	buf = append(buf, 0x1B, 0x45, 0x00)
	// Left Align
	buf = append(buf, 0x1B, 0x61, 0x00)
	buf = append(buf, []byte(fmt.Sprintf("Date:      %s\n", time.Now().Format("02-01-2006 15:04")))...)
	buf = append(buf, []byte(fmt.Sprintf("Pass ID:   GP-%d\n", time.Now().Unix()%100000))...)
	buf = append(buf, []byte(fmt.Sprintf("Farmer:    %s\n", farmerName))...)
	buf = append(buf, []byte(fmt.Sprintf("Produce:   %s\n", cropType))...)
	buf = append(buf, []byte(fmt.Sprintf("Quantity:  %.2f Quintals\n", weightKg/100))...)
	buf = append(buf, []byte(fmt.Sprintf("MSP Rate:  Rs. %.2f / Qtl\n", mandiRate))...)
	buf = append(buf, []byte("--------------------------------\n")...)
	total := (weightKg / 100) * mandiRate
	buf = append(buf, []byte(fmt.Sprintf("TOTAL VAL: Rs. %.2f\n", total))...)
	buf = append(buf, []byte("--------------------------------\n")...)
	// Center Align & Barcode/QR
	buf = append(buf, 0x1B, 0x61, 0x01)
	buf = append(buf, []byte("Payment QR not configured\n\n")...)
	buf = append(buf, []byte("  Keep this receipt for reference  \n\n\n")...)
	// Paper Cut (GS V 66 0)
	buf = append(buf, 0x1D, 0x56, 0x42, 0x00)
	return buf
}

// SendRawToLANPrinter sends ESC/POS byte stream to a network thermal printer.
func SendRawToLANPrinter(printerIP string, port int, data []byte) error {
	if port <= 0 {
		port = 9100
	}
	conn, err := net.DialTimeout("tcp", net.JoinHostPort(printerIP, fmt.Sprint(port)), 4*time.Second)
	if err != nil {
		return err
	}
	defer conn.Close()
	_ = conn.SetWriteDeadline(time.Now().Add(4 * time.Second))
	_, err = conn.Write(data)
	return err
}
