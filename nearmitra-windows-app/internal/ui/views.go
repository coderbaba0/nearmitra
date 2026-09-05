// Package ui provides view rendering routines and Fluent UI component layouts for NearMitra Windows.
package ui

import (
	"fmt"
	"math"
	"unsafe"

	"nearmitra-windows-app/internal/ai"
	"nearmitra-windows-app/internal/calling"
	"nearmitra-windows-app/internal/config"
	"nearmitra-windows-app/internal/iot"
	"nearmitra-windows-app/internal/models"
	"nearmitra-windows-app/internal/streaming"
)

// HitBox stores a clickable rect with an associated action key.
type HitBox struct {
	Key  string
	Rect RECT
}

// DrawRoundedBox draws a styled card or button with rounded corners.
func DrawRoundedBox(hdc uintptr, r RECT, bgColor, borderColor uint32, radius int32) {
	brush, _, _ := pCreateSolidBrush.Call(uintptr(bgColor))
	pen, _, _ := pCreatePen.Call(PS_SOLID, 1, uintptr(borderColor))

	oldBrush, _, _ := pSelectObject.Call(hdc, brush)
	oldPen, _, _ := pSelectObject.Call(hdc, pen)

	pRoundRect.Call(hdc, uintptr(r.Left), uintptr(r.Top), uintptr(r.Right), uintptr(r.Bottom), uintptr(radius), uintptr(radius))

	pSelectObject.Call(hdc, oldBrush)
	pSelectObject.Call(hdc, oldPen)
	pDeleteObject.Call(brush)
	pDeleteObject.Call(pen)
}

// DrawTextSimple renders text with specific color, font, and alignment flags.
func DrawTextSimple(hdc uintptr, text string, r RECT, color uint32, hFont uintptr, flags uint32) {
	if text == "" {
		return
	}
	pSetBkMode.Call(hdc, TRANSPARENT)
	pSetTextColor.Call(hdc, uintptr(color))
	oldFont, _, _ := pSelectObject.Call(hdc, hFont)

	u16 := UTF16Ptr(text)
	rc := r
	pDrawText.Call(hdc, uintptr(unsafe.Pointer(u16)), uintptr(len(text)), uintptr(unsafe.Pointer(&rc)), uintptr(flags|DT_NOPREFIX))

	pSelectObject.Call(hdc, oldFont)
}

// DrawBadge renders a small colored status badge with text.
func DrawBadge(hdc uintptr, text string, x, y int32, bgColor, textColor uint32, hFont uintptr) RECT {
	padX := Scale(10)
	textLen := int32(len(text)) * Scale(7)
	badgeW := textLen + padX*2
	badgeH := Scale(22)

	r := RECT{Left: x, Top: y, Right: x + badgeW, Bottom: y + badgeH}
	DrawRoundedBox(hdc, r, bgColor, bgColor, Scale(10))
	DrawTextSimple(hdc, text, r, textColor, hFont, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
	return r
}

// DrawProgressBar renders a modern rounded progress bar with percentage.
func DrawProgressBar(hdc uintptr, r RECT, progress float64, fillColor, bgColor uint32) {
	DrawRoundedBox(hdc, r, bgColor, bgColor, Scale(6))
	if progress > 0 {
		fillW := int32(float64(r.Right-r.Left) * math.Min(1.0, math.Max(0.0, progress)))
		if fillW > Scale(6) {
			fillR := RECT{Left: r.Left, Top: r.Top, Right: r.Left + fillW, Bottom: r.Bottom}
			DrawRoundedBox(hdc, fillR, fillColor, fillColor, Scale(6))
		}
	}
}

// RenderSidebar draws the navigation sidebar with tabs, branding, and status indicators.
func RenderSidebar(hdc uintptr, bounds RECT, currentTab int, theme FluentPalette, fontTitle, fontBody, fontSmall, fontSubhead uintptr, hitboxes *[]HitBox) {
	// Sidebar Background
	bgBrush, _, _ := pCreateSolidBrush.Call(uintptr(theme.BgSidebar))
	pFillRect.Call(hdc, uintptr(unsafe.Pointer(&bounds)), bgBrush)
	pDeleteObject.Call(bgBrush)

	// Border right line
	pen, _, _ := pCreatePen.Call(PS_SOLID, 1, uintptr(theme.BorderColor))
	oldPen, _, _ := pSelectObject.Call(hdc, pen)
	lineR := RECT{Left: bounds.Right - 1, Top: bounds.Top, Right: bounds.Right, Bottom: bounds.Bottom}
	pFillRect.Call(hdc, uintptr(unsafe.Pointer(&lineR)), pen)
	pSelectObject.Call(hdc, oldPen)
	pDeleteObject.Call(pen)

	// Brand Header Card
	brandCardR := RECT{Left: bounds.Left + Scale(12), Top: bounds.Top + Scale(14), Right: bounds.Right - Scale(12), Bottom: bounds.Top + Scale(66)}
	DrawRoundedBox(hdc, brandCardR, theme.BgCard, theme.BorderColor, Scale(8))

	headerR := RECT{Left: brandCardR.Left + Scale(12), Top: brandCardR.Top + Scale(6), Right: brandCardR.Right - Scale(12), Bottom: brandCardR.Top + Scale(28)}
	DrawTextSimple(hdc, "NearMitra", headerR, theme.PrimaryGreen, fontTitle, DT_LEFT|DT_VCENTER|DT_SINGLELINE)

	tagR := RECT{Left: brandCardR.Left + Scale(12), Top: brandCardR.Top + Scale(28), Right: brandCardR.Right - Scale(12), Bottom: brandCardR.Bottom - Scale(6)}
	DrawTextSimple(hdc, "Local AI & High-Speed P2P", tagR, theme.TextMuted, fontSmall, DT_LEFT|DT_VCENTER|DT_SINGLELINE)

	// Navigation Tabs list (8 items)
	tabs := []struct {
		ID    int
		Title string
		Icon  string
	}{
		{0, "Radar & Peers", "📡"},
		{1, "P2P Chat", "💬"},
		{2, "CCTV & Vision AI", "📹"},
		{3, "Voice & Walkie", "📞"},
		{4, "AI Fleet Hub", "🧠"},
		{5, "IoT & Hardware", "🔌"},
		{6, "Transfers & Logs", "📊"},
		{7, "Settings & About", "⚙️"},
	}

	tabY := bounds.Top + Scale(76)
	tabH := Scale(38)
	tabPad := Scale(10)

	for _, tab := range tabs {
		btnR := RECT{
			Left:   bounds.Left + tabPad,
			Top:    tabY,
			Right:  bounds.Right - tabPad,
			Bottom: tabY + tabH,
		}

		isSelected := currentTab == tab.ID
		bgColor := theme.BgSidebar
		borderColor := theme.BgSidebar
		textColor := theme.TextBody
		if isSelected {
			bgColor = theme.PrimaryGreen
			borderColor = theme.PrimaryGreen
			textColor = RGB(255, 255, 255)
		}

		DrawRoundedBox(hdc, btnR, bgColor, borderColor, Scale(8))

		// Left accent bar on active tab
		if isSelected {
			barR := RECT{Left: btnR.Left + Scale(4), Top: btnR.Top + Scale(8), Right: btnR.Left + Scale(7), Bottom: btnR.Bottom - Scale(8)}
			DrawRoundedBox(hdc, barR, RGB(255, 255, 255), RGB(255, 255, 255), Scale(2))
		}

		labelR := RECT{Left: btnR.Left + Scale(14), Top: btnR.Top, Right: btnR.Right - Scale(8), Bottom: btnR.Bottom}
		DrawTextSimple(hdc, fmt.Sprintf("%s  %s", tab.Icon, tab.Title), labelR, textColor, fontBody, DT_LEFT|DT_VCENTER|DT_SINGLELINE)

		*hitboxes = append(*hitboxes, HitBox{
			Key:  fmt.Sprintf("TAB_%d", tab.ID),
			Rect: btnR,
		})

		tabY += tabH + Scale(5)
	}

	// Footer Version Info
	footerR := RECT{
		Left:   bounds.Left + Scale(14),
		Top:    bounds.Bottom - Scale(34),
		Right:  bounds.Right - Scale(14),
		Bottom: bounds.Bottom - Scale(10),
	}
	DrawTextSimple(hdc, "NearMitra v2.0 • Win11 Fluent", footerR, theme.TextMuted, fontSmall, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
}

// RenderRadarView renders the Radar screen with concentric rings and active peer cards.
func RenderRadarView(hdc uintptr, bounds RECT, peers []*models.Peer, router models.RouterInfo, theme FluentPalette, fontTitle, fontBody, fontSmall, fontSubhead uintptr, hitboxes *[]HitBox) {
	// Top Header
	headerR := RECT{Left: bounds.Left + Scale(24), Top: bounds.Top + Scale(18), Right: bounds.Right - Scale(24), Bottom: bounds.Top + Scale(48)}
	DrawTextSimple(hdc, "Discovery & Wi-Fi Radar", headerR, theme.TextTitle, fontTitle, DT_LEFT|DT_VCENTER|DT_SINGLELINE)

	// Quick Action Buttons
	btnSendFileR := RECT{Left: bounds.Right - Scale(260), Top: bounds.Top + Scale(16), Right: bounds.Right - Scale(140), Bottom: bounds.Top + Scale(52)}
	DrawRoundedBox(hdc, btnSendFileR, theme.PrimaryGreen, theme.PrimaryGreen, Scale(6))
	DrawTextSimple(hdc, "📁 Send File", btnSendFileR, RGB(255, 255, 255), fontBody, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
	*hitboxes = append(*hitboxes, HitBox{Key: "BTN_SEND_FILE", Rect: btnSendFileR})

	btnSendFolderR := RECT{Left: bounds.Right - Scale(130), Top: bounds.Top + Scale(16), Right: bounds.Right - Scale(24), Bottom: bounds.Top + Scale(52)}
	DrawRoundedBox(hdc, btnSendFolderR, theme.BgCard, theme.BorderColor, Scale(6))
	DrawTextSimple(hdc, "📦 Send Folder", btnSendFolderR, theme.TextTitle, fontBody, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
	*hitboxes = append(*hitboxes, HitBox{Key: "BTN_SEND_FOLDER", Rect: btnSendFolderR})

	// Wi-Fi Status Bar Card
	wifiBarR := RECT{Left: bounds.Left + Scale(24), Top: bounds.Top + Scale(60), Right: bounds.Right - Scale(24), Bottom: bounds.Top + Scale(96)}
	DrawRoundedBox(hdc, wifiBarR, theme.BgCard, theme.BorderColor, Scale(8))

	wifiText := fmt.Sprintf("📶  %s  •  IP: %s  •  Speed: %s  •  Discovered Peers: %d", router.SSID, router.IPv4, router.LinkSpeed, len(peers))
	DrawTextSimple(hdc, wifiText, RECT{Left: wifiBarR.Left + Scale(14), Top: wifiBarR.Top, Right: wifiBarR.Right - Scale(14), Bottom: wifiBarR.Bottom}, theme.PrimaryGreen, fontSmall, DT_LEFT|DT_VCENTER|DT_SINGLELINE)

	// Peer Cards Grid
	cardY := bounds.Top + Scale(110)
	cardW := (bounds.Right - bounds.Left - Scale(72)) / 2
	cardH := Scale(130)

	if len(peers) == 0 {
		emptyR := RECT{Left: bounds.Left + Scale(24), Top: cardY + Scale(20), Right: bounds.Right - Scale(24), Bottom: cardY + Scale(200)}
		DrawRoundedBox(hdc, emptyR, theme.BgCard, theme.BorderColor, Scale(12))

		DrawTextSimple(hdc, "📡  Scanning for Nearby Android & Windows Devices...", RECT{Left: emptyR.Left, Top: emptyR.Top + Scale(45), Right: emptyR.Right, Bottom: emptyR.Top + Scale(75)}, theme.TextTitle, fontSubhead, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
		hintText := "Ensure Wi-Fi or Hotspot is active on all devices. Discovery runs automatically on Multicast Port 43888."
		DrawTextSimple(hdc, hintText, RECT{Left: emptyR.Left + Scale(20), Top: emptyR.Top + Scale(80), Right: emptyR.Right - Scale(20), Bottom: emptyR.Top + Scale(120)}, theme.TextMuted, fontSmall, DT_CENTER|DT_WORDBREAK)
		return
	}

	for i, peer := range peers {
		if i >= 6 {
			break
		}
		col := i % 2
		row := i / 2

		left := bounds.Left + Scale(24) + int32(col)*(cardW+Scale(24))
		top := cardY + int32(row)*(cardH+Scale(16))
		cardR := RECT{Left: left, Top: top, Right: left + cardW, Bottom: top + cardH}

		DrawRoundedBox(hdc, cardR, theme.BgCard, theme.BorderColor, Scale(10))

		// Peer Device Icon & Name
		iconText := "📱"
		if peer.ComputeInfo.Device != "" && (peer.ComputeInfo.Device == "Windows amd64" || peer.ComputeInfo.Device == "Windows arm64") {
			iconText = "💻"
		}
		nameR := RECT{Left: cardR.Left + Scale(16), Top: cardR.Top + Scale(12), Right: cardR.Right - Scale(110), Bottom: cardR.Top + Scale(38)}
		DrawTextSimple(hdc, fmt.Sprintf("%s  %s", iconText, peer.Name), nameR, theme.TextTitle, fontSubhead, DT_LEFT|DT_VCENTER|DT_SINGLELINE|DT_END_ELLIPSIS)

		// Online badge
		DrawBadge(hdc, "ONLINE", cardR.Right-Scale(90), cardR.Top+Scale(12), theme.BadgeOnline, RGB(255, 255, 255), fontSmall)

		// IP and Capabilities
		ipR := RECT{Left: cardR.Left + Scale(16), Top: cardR.Top + Scale(42), Right: cardR.Right - Scale(16), Bottom: cardR.Top + Scale(64)}
		capText := fmt.Sprintf("IP: %s : %d", peer.IP, peer.Port)
		if peer.IsAiHost {
			capText += fmt.Sprintf("  •  AI Host (%s)", peer.AIProvider)
		}
		DrawTextSimple(hdc, capText, ipR, theme.TextMuted, fontSmall, DT_LEFT|DT_VCENTER|DT_SINGLELINE)

		// Action buttons: Chat, Send File, Voice Call
		btnChatR := RECT{Left: cardR.Left + Scale(16), Top: cardR.Bottom - Scale(44), Right: cardR.Left + Scale(100), Bottom: cardR.Bottom - Scale(12)}
		DrawRoundedBox(hdc, btnChatR, theme.PrimaryGreen, theme.PrimaryGreen, Scale(6))
		DrawTextSimple(hdc, "💬 Chat", btnChatR, RGB(255, 255, 255), fontSmall, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
		*hitboxes = append(*hitboxes, HitBox{Key: fmt.Sprintf("PEER_CHAT_%s", peer.ID), Rect: btnChatR})

		btnShareR := RECT{Left: cardR.Left + Scale(108), Top: cardR.Bottom - Scale(44), Right: cardR.Left + Scale(200), Bottom: cardR.Bottom - Scale(12)}
		DrawRoundedBox(hdc, btnShareR, theme.BgCardHover, theme.BorderColor, Scale(6))
		DrawTextSimple(hdc, "📁 Send File", btnShareR, theme.TextBody, fontSmall, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
		*hitboxes = append(*hitboxes, HitBox{Key: fmt.Sprintf("PEER_SEND_%s", peer.ID), Rect: btnShareR})

		btnCallR := RECT{Left: cardR.Left + Scale(208), Top: cardR.Bottom - Scale(44), Right: cardR.Left + Scale(300), Bottom: cardR.Bottom - Scale(12)}
		DrawRoundedBox(hdc, btnCallR, theme.AccentCCTV, theme.AccentCCTV, Scale(6))
		DrawTextSimple(hdc, "📞 Voice Call", btnCallR, RGB(255, 255, 255), fontSmall, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
		*hitboxes = append(*hitboxes, HitBox{Key: fmt.Sprintf("PEER_CALL_%s", peer.ID), Rect: btnCallR})
	}
}

// RenderChatView renders the Chat conversation stream, bubbles, reaction bar, and input controls.
func RenderChatView(hdc uintptr, bounds RECT, activePeer *models.Peer, messages []models.ChatMessage, typingStatus string, theme FluentPalette, fontTitle, fontBody, fontSmall, fontSubhead uintptr, hitboxes *[]HitBox) {
	// Chat Header Card
	headCardR := RECT{Left: bounds.Left + Scale(24), Top: bounds.Top + Scale(16), Right: bounds.Right - Scale(24), Bottom: bounds.Top + Scale(70)}
	DrawRoundedBox(hdc, headCardR, theme.BgCard, theme.BorderColor, Scale(8))

	peerTitle := "Select a nearby peer to start chatting"
	peerSub := "Local high-speed P2P encrypted messaging"
	if activePeer != nil {
		peerTitle = fmt.Sprintf("Chat with %s", activePeer.Name)
		peerSub = fmt.Sprintf("IP: %s : %d  •  Status: Connected", activePeer.IP, activePeer.Port)
	}
	DrawTextSimple(hdc, peerTitle, RECT{Left: headCardR.Left + Scale(16), Top: headCardR.Top + Scale(8), Right: headCardR.Right - Scale(16), Bottom: headCardR.Top + Scale(32)}, theme.TextTitle, fontSubhead, DT_LEFT|DT_VCENTER|DT_SINGLELINE)

	subColor := theme.TextMuted
	if typingStatus != "" {
		peerSub = typingStatus
		subColor = theme.PrimaryGreen
	}
	DrawTextSimple(hdc, peerSub, RECT{Left: headCardR.Left + Scale(16), Top: headCardR.Top + Scale(32), Right: headCardR.Right - Scale(16), Bottom: headCardR.Bottom - Scale(6)}, subColor, fontSmall, DT_LEFT|DT_VCENTER|DT_SINGLELINE)

	// Message list area
	listTop := bounds.Top + Scale(80)
	listBottom := bounds.Bottom - Scale(75)

	msgY := listBottom - Scale(15)
	maxVisible := 10
	startIdx := len(messages) - 1

	reactionIcons := []string{"👍", "❤️", "👎", "🤔", "😂"}

	for i := startIdx; i >= 0 && maxVisible > 0; i-- {
		msg := messages[i]
		maxVisible--

		bubbleW := Scale(380)
		bubbleH := Scale(62)
		if len(msg.Reaction) > 0 {
			bubbleH += Scale(24)
		}

		var bubbleR RECT
		var bgColor uint32
		var textColor uint32
		if msg.Mine {
			bubbleR = RECT{Left: bounds.Right - Scale(24) - bubbleW, Top: msgY - bubbleH, Right: bounds.Right - Scale(24), Bottom: msgY}
			bgColor = theme.BubbleMine
			textColor = RGB(236, 253, 245)
		} else {
			bubbleR = RECT{Left: bounds.Left + Scale(24), Top: msgY - bubbleH, Right: bounds.Left + Scale(24) + bubbleW, Bottom: msgY}
			bgColor = theme.BubblePeer
			textColor = theme.TextBody
		}

		if bubbleR.Top < listTop {
			break
		}

		DrawRoundedBox(hdc, bubbleR, bgColor, theme.BorderColor, Scale(10))

		// Sender & time
		metaR := RECT{Left: bubbleR.Left + Scale(12), Top: bubbleR.Top + Scale(6), Right: bubbleR.Right - Scale(60), Bottom: bubbleR.Top + Scale(24)}
		metaText := fmt.Sprintf("%s  •  %s", msg.Sender, msg.At.Format("15:04:05"))
		DrawTextSimple(hdc, metaText, metaR, theme.TextMuted, fontSmall, DT_LEFT|DT_VCENTER|DT_SINGLELINE)

		// Copy button
		btnCopyR := RECT{Left: bubbleR.Right - Scale(50), Top: bubbleR.Top + Scale(6), Right: bubbleR.Right - Scale(10), Bottom: bubbleR.Top + Scale(24)}
		DrawTextSimple(hdc, "Copy", btnCopyR, theme.TextMuted, fontSmall, DT_RIGHT|DT_VCENTER|DT_SINGLELINE)
		*hitboxes = append(*hitboxes, HitBox{Key: fmt.Sprintf("COPY_MSG_%s", msg.ID), Rect: btnCopyR})

		// Message Text
		textR := RECT{Left: bubbleR.Left + Scale(12), Top: bubbleR.Top + Scale(26), Right: bubbleR.Right - Scale(12), Bottom: bubbleR.Top + Scale(54)}
		DrawTextSimple(hdc, msg.Text, textR, textColor, fontBody, DT_LEFT|DT_WORDBREAK)

		// Reaction bar
		rxY := bubbleR.Top + Scale(54)
		rxX := bubbleR.Left + Scale(12)
		for _, emoji := range reactionIcons {
			emojiR := RECT{Left: rxX, Top: rxY, Right: rxX + Scale(28), Bottom: rxY + Scale(22)}
			DrawTextSimple(hdc, emoji, emojiR, theme.TextBody, fontSmall, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
			*hitboxes = append(*hitboxes, HitBox{Key: fmt.Sprintf("REACT_%s_%s", msg.ID, emoji), Rect: emojiR})
			rxX += Scale(30)
		}

		msgY -= bubbleH + Scale(10)
	}

	// Bottom Input Bar Card
	inputBarR := RECT{Left: bounds.Left + Scale(24), Top: bounds.Bottom - Scale(62), Right: bounds.Right - Scale(24), Bottom: bounds.Bottom - Scale(14)}
	DrawRoundedBox(hdc, inputBarR, theme.BgCard, theme.BorderColor, Scale(8))

	// Attach File Button (+)
	btnAttachR := RECT{Left: inputBarR.Left + Scale(6), Top: inputBarR.Top + Scale(6), Right: inputBarR.Left + Scale(44), Bottom: inputBarR.Bottom - Scale(6)}
	DrawRoundedBox(hdc, btnAttachR, theme.BgCardHover, theme.BorderColor, Scale(6))
	DrawTextSimple(hdc, "+", btnAttachR, theme.TextTitle, fontTitle, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
	*hitboxes = append(*hitboxes, HitBox{Key: "BTN_CHAT_ATTACH", Rect: btnAttachR})

	// Send Button
	btnSendR := RECT{Left: inputBarR.Right - Scale(90), Top: inputBarR.Top + Scale(6), Right: inputBarR.Right - Scale(6), Bottom: inputBarR.Bottom - Scale(6)}
	DrawRoundedBox(hdc, btnSendR, theme.PrimaryGreen, theme.PrimaryGreen, Scale(6))
	DrawTextSimple(hdc, "Send ✈", btnSendR, RGB(255, 255, 255), fontBody, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
	*hitboxes = append(*hitboxes, HitBox{Key: "BTN_CHAT_SEND", Rect: btnSendR})
}

// RenderCCTVView renders live video stream feed, OpenCV filter selector, live stream recording, and telemetry HUD.
func RenderCCTVView(hdc uintptr, bounds RECT, streamState *streaming.StreamState, theme FluentPalette, fontTitle, fontBody, fontSmall, fontSubhead uintptr, hitboxes *[]HitBox) {
	// Top Header
	headerR := RECT{Left: bounds.Left + Scale(24), Top: bounds.Top + Scale(16), Right: bounds.Right - Scale(24), Bottom: bounds.Top + Scale(44)}
	DrawTextSimple(hdc, "CCTV Surveillance & Computer Vision AI", headerR, theme.TextTitle, fontTitle, DT_LEFT|DT_VCENTER|DT_SINGLELINE)

	// Filter Selection Bar (OpenCV-Style Pipeline)
	filters := []streaming.CVFilter{
		streaming.CVFilterNone,
		streaming.CVFilterMotionDetection,
		streaming.CVFilterCropHealth,
		streaming.CVFilterNightVision,
		streaming.CVFilterEdgeDetect,
		streaming.CVFilterThermal,
	}

	filterY := bounds.Top + Scale(48)
	filterX := bounds.Left + Scale(24)
	btnFW := Scale(120)
	btnFH := Scale(28)

	for _, f := range filters {
		btnFR := RECT{Left: filterX, Top: filterY, Right: filterX + btnFW, Bottom: filterY + btnFH}
		isSelected := streamState != nil && streamState.SelectedFilter == f
		bgColor := theme.BgCard
		textColor := theme.TextBody
		borderColor := theme.BorderColor
		if isSelected {
			bgColor = theme.AccentCCTV
			borderColor = theme.AccentCCTV
			textColor = RGB(255, 255, 255)
		}
		DrawRoundedBox(hdc, btnFR, bgColor, borderColor, Scale(6))

		shortName := string(f)
		if len(shortName) > 16 {
			shortName = shortName[:14] + ".."
		}
		DrawTextSimple(hdc, shortName, btnFR, textColor, fontSmall, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
		*hitboxes = append(*hitboxes, HitBox{Key: fmt.Sprintf("SET_CV_FILTER_%s", f), Rect: btnFR})

		filterX += btnFW + Scale(8)
	}

	// Stream Viewport Monitor Card
	viewR := RECT{Left: bounds.Left + Scale(24), Top: filterY + btnFH + Scale(12), Right: bounds.Right - Scale(24), Bottom: bounds.Bottom - Scale(76)}
	DrawRoundedBox(hdc, viewR, RGB(8, 12, 20), theme.BorderColor, Scale(10))

	// Live Stream HUD Overlay (Top-Left)
	hudR := RECT{Left: viewR.Left + Scale(16), Top: viewR.Top + Scale(14), Right: viewR.Left + Scale(320), Bottom: viewR.Top + Scale(70)}
	DrawRoundedBox(hdc, hudR, RGB(15, 23, 42), theme.BorderColor, Scale(6))

	hudText1 := "🔴 LIVE FEED • 1080p FHD • 30 FPS"
	hudText2 := fmt.Sprintf("Pipeline: %s", streamState.SelectedFilter)
	DrawTextSimple(hdc, hudText1, RECT{Left: hudR.Left + Scale(10), Top: hudR.Top + Scale(6), Right: hudR.Right, Bottom: hudR.Top + Scale(24)}, theme.BadgeOnline, fontSmall, DT_LEFT|DT_VCENTER|DT_SINGLELINE)
	DrawTextSimple(hdc, hudText2, RECT{Left: hudR.Left + Scale(10), Top: hudR.Top + Scale(26), Right: hudR.Right, Bottom: hudR.Top + Scale(46)}, theme.TextTitle, fontSmall, DT_LEFT|DT_VCENTER|DT_SINGLELINE)

	// Live Stream HUD Overlay (Top-Right: Recording Status)
	if streamState != nil && streamState.IsRecording {
		recR := RECT{Left: viewR.Right - Scale(160), Top: viewR.Top + Scale(14), Right: viewR.Right - Scale(16), Bottom: viewR.Top + Scale(50)}
		DrawRoundedBox(hdc, recR, RGB(220, 38, 38), RGB(220, 38, 38), Scale(6))
		DrawTextSimple(hdc, "⏺ REC 00:01:42", recR, RGB(255, 255, 255), fontSubhead, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
	}

	// Center Monitor Text
	monitorCenterR := RECT{Left: viewR.Left, Top: viewR.Top + (viewR.Bottom-viewR.Top)/2 - Scale(25), Right: viewR.Right, Bottom: viewR.Top + (viewR.Bottom-viewR.Top)/2 + Scale(25)}
	if streamState == nil || !streamState.Active {
		DrawTextSimple(hdc, "📹  Live Camera Feed Ready • Click smartphone in Radar to stream", monitorCenterR, theme.TextMuted, fontSubhead, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
	} else {
		DrawTextSimple(hdc, "[ LIVE COMPUTER VISION STREAM ACTIVE ]", monitorCenterR, theme.BadgeOnline, fontTitle, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
	}

	// AI Filter Diagnostic Banner (Bottom of Viewport)
	if streamState != nil && streamState.SelectedFilter == streaming.CVFilterCropHealth {
		diagR := RECT{Left: viewR.Left + Scale(16), Top: viewR.Bottom - Scale(44), Right: viewR.Right - Scale(16), Bottom: viewR.Bottom - Scale(14)}
		DrawRoundedBox(hdc, diagR, RGB(6, 95, 70), theme.PrimaryGreen, Scale(6))
		DrawTextSimple(hdc, fmt.Sprintf("🍃 %s", streamState.CropHealthStatus), diagR, RGB(236, 253, 245), fontSmall, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
	} else if streamState != nil && streamState.SelectedFilter == streaming.CVFilterMotionDetection {
		diagR := RECT{Left: viewR.Left + Scale(16), Top: viewR.Bottom - Scale(44), Right: viewR.Right - Scale(16), Bottom: viewR.Bottom - Scale(14)}
		DrawRoundedBox(hdc, diagR, RGB(180, 83, 9), RGB(245, 158, 11), Scale(6))
		DrawTextSimple(hdc, fmt.Sprintf("⚠️ Motion Activity Index: %d%% • Cattle / Intruder tracking grid active", streamState.MotionScore), diagR, RGB(255, 255, 255), fontSmall, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
	}

	// Bottom Action Bar: Recording, Snapshots, Torch, Flip
	barY := bounds.Bottom - Scale(60)

	// Record Button
	btnRecR := RECT{Left: bounds.Left + Scale(24), Top: barY, Right: bounds.Left + Scale(160), Bottom: barY + Scale(44)}
	recBg := RGB(220, 38, 38)
	recText := "⏺ Start REC"
	if streamState != nil && streamState.IsRecording {
		recBg = theme.BgCardHover
		recText = "⏹ Stop REC"
	}
	DrawRoundedBox(hdc, btnRecR, recBg, recBg, Scale(6))
	DrawTextSimple(hdc, recText, btnRecR, RGB(255, 255, 255), fontBody, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
	*hitboxes = append(*hitboxes, HitBox{Key: "BTN_CCTV_RECORD", Rect: btnRecR})

	// Snapshot Button
	btnSnapR := RECT{Left: bounds.Left + Scale(170), Top: barY, Right: bounds.Left + Scale(300), Bottom: barY + Scale(44)}
	DrawRoundedBox(hdc, btnSnapR, theme.AccentCCTV, theme.AccentCCTV, Scale(6))
	DrawTextSimple(hdc, "📸 Snapshot", btnSnapR, RGB(255, 255, 255), fontBody, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
	*hitboxes = append(*hitboxes, HitBox{Key: "BTN_CCTV_SNAPSHOT", Rect: btnSnapR})

	// Flashlight Button
	torchText := "🔦 Torch: OFF"
	if streamState != nil && streamState.TorchOn {
		torchText = "🔦 Torch: ON"
	}
	btnTorchR := RECT{Left: bounds.Left + Scale(310), Top: barY, Right: bounds.Left + Scale(440), Bottom: barY + Scale(44)}
	DrawRoundedBox(hdc, btnTorchR, theme.BgCard, theme.BorderColor, Scale(6))
	DrawTextSimple(hdc, torchText, btnTorchR, theme.TextTitle, fontBody, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
	*hitboxes = append(*hitboxes, HitBox{Key: "BTN_CCTV_TORCH", Rect: btnTorchR})

	// Flip Lens Button
	btnFlipR := RECT{Left: bounds.Left + Scale(450), Top: barY, Right: bounds.Left + Scale(580), Bottom: barY + Scale(44)}
	DrawRoundedBox(hdc, btnFlipR, theme.BgCard, theme.BorderColor, Scale(6))
	DrawTextSimple(hdc, "🔄 Flip Lens", btnFlipR, theme.TextTitle, fontBody, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
	*hitboxes = append(*hitboxes, HitBox{Key: "BTN_CCTV_FLIP", Rect: btnFlipR})
}

// RenderCallView renders the Voice & Walkie-Talkie Calling console with Push-To-Talk and Audio Waveform Visualizer.
func RenderCallView(hdc uintptr, bounds RECT, callState *calling.CallState, theme FluentPalette, fontTitle, fontBody, fontSmall, fontSubhead uintptr, hitboxes *[]HitBox) {
	// Top Header
	headerR := RECT{Left: bounds.Left + Scale(24), Top: bounds.Top + Scale(18), Right: bounds.Right - Scale(24), Bottom: bounds.Top + Scale(48)}
	DrawTextSimple(hdc, "Voice & Walkie-Talkie Hub", headerR, theme.TextTitle, fontTitle, DT_LEFT|DT_VCENTER|DT_SINGLELINE)

	subR := RECT{Left: bounds.Left + Scale(24), Top: bounds.Top + Scale(48), Right: bounds.Right - Scale(24), Bottom: bounds.Top + Scale(70)}
	DrawTextSimple(hdc, "Low-Latency WebRTC P2P Voice • AI Noise Suppression • Push-To-Talk (PTT)", subR, theme.AccentCCTV, fontSmall, DT_LEFT|DT_VCENTER|DT_SINGLELINE)

	// Call Status Main Card
	mainCardR := RECT{Left: bounds.Left + Scale(24), Top: bounds.Top + Scale(80), Right: bounds.Right - Scale(24), Bottom: bounds.Bottom - Scale(140)}
	DrawRoundedBox(hdc, mainCardR, theme.BgCard, theme.BorderColor, Scale(12))

	peerName := "Select a peer from Radar to start calling"
	callStatus := "Channel: Ready / Idle"
	if callState != nil && callState.Active {
		peerName = fmt.Sprintf("Connected with %s", callState.PeerName)
		callStatus = fmt.Sprintf("Codec: %s  •  Latency: %d ms", callState.AudioCodec, callState.LatencyMs)
	}

	peerR := RECT{Left: mainCardR.Left + Scale(24), Top: mainCardR.Top + Scale(24), Right: mainCardR.Right - Scale(24), Bottom: mainCardR.Top + Scale(54)}
	DrawTextSimple(hdc, peerName, peerR, theme.TextTitle, fontTitle, DT_CENTER|DT_VCENTER|DT_SINGLELINE)

	statusR := RECT{Left: mainCardR.Left + Scale(24), Top: mainCardR.Top + Scale(56), Right: mainCardR.Right - Scale(24), Bottom: mainCardR.Top + Scale(80)}
	DrawTextSimple(hdc, callStatus, statusR, theme.PrimaryGreen, fontSubhead, DT_CENTER|DT_VCENTER|DT_SINGLELINE)

	// Audio Waveform Visualizer (8 animated vertical frequency bars)
	waveY := mainCardR.Top + Scale(110)
	waveCenter := (mainCardR.Right + mainCardR.Left) / 2
	barW := Scale(16)
	barSpacing := Scale(12)
	totalW := 8*barW + 7*barSpacing
	startX := waveCenter - totalW/2

	levels := [8]int{20, 35, 60, 85, 75, 50, 30, 15}
	if callState != nil && callState.PTTActive {
		levels = callState.AudioLevels
	}

	for i, lvl := range levels {
		barH := int32((lvl * int(Scale(80))) / 100)
		bx := startX + int32(i)*(barW+barSpacing)
		by := waveY + Scale(80) - barH
		barR := RECT{Left: bx, Top: by, Right: bx + barW, Bottom: waveY + Scale(80)}

		barColor := theme.AccentCCTV
		if callState != nil && callState.PTTActive {
			barColor = theme.PrimaryGreen
		}
		DrawRoundedBox(hdc, barR, barColor, barColor, Scale(4))
	}

	// Audio Controls (PTT Push-to-Talk Big Button)
	pttY := mainCardR.Bottom - Scale(90)
	pttW := Scale(220)
	pttR := RECT{Left: waveCenter - pttW/2, Top: pttY, Right: waveCenter + pttW/2, Bottom: pttY + Scale(60)}

	pttBg := theme.BgCardHover
	pttText := "🎙️ HOLD TO TALK (PTT)"
	if callState != nil && callState.PTTActive {
		pttBg = theme.PrimaryGreen
		pttText = "🔊 TRANSMITTING..."
	}
	DrawRoundedBox(hdc, pttR, pttBg, theme.BorderColor, Scale(30))
	DrawTextSimple(hdc, pttText, pttR, RGB(255, 255, 255), fontSubhead, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
	*hitboxes = append(*hitboxes, HitBox{Key: "CALL_TOGGLE_PTT", Rect: pttR})

	// Bottom Action Bar: Mute, Noise Suppression, End Call
	barBottomY := bounds.Bottom - Scale(110)
	btnMuteR := RECT{Left: bounds.Left + Scale(24), Top: barBottomY, Right: bounds.Left + Scale(180), Bottom: barBottomY + Scale(45)}
	muteText := "🎤 Mic: Unmuted"
	if callState != nil && callState.Muted {
		muteText = "🔇 Mic: Muted"
	}
	DrawRoundedBox(hdc, btnMuteR, theme.BgCard, theme.BorderColor, Scale(8))
	DrawTextSimple(hdc, muteText, btnMuteR, theme.TextTitle, fontBody, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
	*hitboxes = append(*hitboxes, HitBox{Key: "CALL_TOGGLE_MUTE", Rect: btnMuteR})

	btnNSR := RECT{Left: bounds.Left + Scale(190), Top: barBottomY, Right: bounds.Left + Scale(380), Bottom: barBottomY + Scale(45)}
	nsText := "⚡ AI Noise Filter: ON"
	if callState != nil && !callState.NoiseSuppressionActive {
		nsText = "⚡ AI Noise Filter: OFF"
	}
	DrawRoundedBox(hdc, btnNSR, theme.BgCard, theme.BorderColor, Scale(8))
	DrawTextSimple(hdc, nsText, btnNSR, theme.TextTitle, fontBody, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
	*hitboxes = append(*hitboxes, HitBox{Key: "CALL_TOGGLE_NOISE", Rect: btnNSR})

	btnEndR := RECT{Left: bounds.Right - Scale(180), Top: barBottomY, Right: bounds.Right - Scale(24), Bottom: barBottomY + Scale(45)}
	DrawRoundedBox(hdc, btnEndR, RGB(220, 38, 38), RGB(220, 38, 38), Scale(8))
	DrawTextSimple(hdc, "❌ End Call", btnEndR, RGB(255, 255, 255), fontBody, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
	*hitboxes = append(*hitboxes, HitBox{Key: "CALL_END", Rect: btnEndR})
}

// RenderAIFleetView renders the AI compute mesh, preset templates, and model switcher.
func RenderAIFleetView(hdc uintptr, bounds RECT, aiCfg models.AIConfig, hw models.HardwareComputeInfo, theme FluentPalette, fontTitle, fontBody, fontSmall, fontSubhead uintptr, hitboxes *[]HitBox) {
	headerR := RECT{Left: bounds.Left + Scale(24), Top: bounds.Top + Scale(16), Right: bounds.Right - Scale(24), Bottom: bounds.Top + Scale(44)}
	DrawTextSimple(hdc, "AI Fleet Hub & Farming Multi-LLM", headerR, theme.TextTitle, fontTitle, DT_LEFT|DT_VCENTER|DT_SINGLELINE)

	subR := RECT{Left: bounds.Left + Scale(24), Top: bounds.Top + Scale(44), Right: bounds.Right - Scale(24), Bottom: bounds.Top + Scale(66)}
	DrawTextSimple(hdc, "Dual-Tier Reasoning Engine: Local Ollama (Qwen 2.5 / DeepSeek-R1) • Cloud Gemini 3.5 & GPT-4o", subR, theme.AccentAI, fontSmall, DT_LEFT|DT_VCENTER|DT_SINGLELINE)

	// Model Switcher Bar
	modelsList := []string{"Gemini 3.5 Pro", "ChatGPT-4o", "Qwen 2.5 (Local)", "DeepSeek-R1"}
	modelX := bounds.Left + Scale(24)
	modelY := bounds.Top + Scale(72)
	modelW := Scale(140)
	modelH := Scale(32)

	for _, m := range modelsList {
		btnMR := RECT{Left: modelX, Top: modelY, Right: modelX + modelW, Bottom: modelY + modelH}
		isSelected := (m == "Gemini 3.5 Pro" && aiCfg.Provider == "gemini") || (m == "ChatGPT-4o" && aiCfg.Provider == "openai") || ((m == "Qwen 2.5 (Local)" || m == "DeepSeek-R1") && aiCfg.Provider == "ollama")
		bgColor := theme.BgCard
		textColor := theme.TextBody
		borderColor := theme.BorderColor
		if isSelected {
			bgColor = theme.AccentAI
			borderColor = theme.AccentAI
			textColor = RGB(255, 255, 255)
		}
		DrawRoundedBox(hdc, btnMR, bgColor, borderColor, Scale(6))
		DrawTextSimple(hdc, m, btnMR, textColor, fontSmall, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
		*hitboxes = append(*hitboxes, HitBox{Key: fmt.Sprintf("SET_AI_MODEL_%s", m), Rect: btnMR})
		modelX += modelW + Scale(10)
	}

	// 4 Kisan & Agricultural Preset Prompt Cards (2x2 Grid)
	presets := ai.Get().GetPresets()
	gridTop := modelY + modelH + Scale(12)
	cardW := (bounds.Right - bounds.Left - Scale(60)) / 2
	cardH := Scale(76)

	for i, p := range presets {
		if i >= 4 {
			break
		}
		col := i % 2
		row := i / 2
		left := bounds.Left + Scale(24) + int32(col)*(cardW+Scale(12))
		top := gridTop + int32(row)*(cardH+Scale(10))
		cardR := RECT{Left: left, Top: top, Right: left + cardW, Bottom: top + cardH}

		DrawRoundedBox(hdc, cardR, theme.BgCard, theme.BorderColor, Scale(8))

		titleR := RECT{Left: cardR.Left + Scale(12), Top: cardR.Top + Scale(8), Right: cardR.Right - Scale(80), Bottom: cardR.Top + Scale(28)}
		DrawTextSimple(hdc, p.Title, titleR, theme.TextTitle, fontBody, DT_LEFT|DT_VCENTER|DT_SINGLELINE)

		btnRunR := RECT{Left: cardR.Right - Scale(74), Top: cardR.Top + Scale(8), Right: cardR.Right - Scale(10), Bottom: cardR.Top + Scale(32)}
		DrawRoundedBox(hdc, btnRunR, theme.AccentAI, theme.AccentAI, Scale(6))
		DrawTextSimple(hdc, "Run ⚡", btnRunR, RGB(255, 255, 255), fontSmall, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
		*hitboxes = append(*hitboxes, HitBox{Key: fmt.Sprintf("RUN_AI_PRESET_%d", i), Rect: btnRunR})

		promptR := RECT{Left: cardR.Left + Scale(12), Top: cardR.Top + Scale(32), Right: cardR.Right - Scale(12), Bottom: cardR.Bottom - Scale(6)}
		DrawTextSimple(hdc, p.PromptText, promptR, theme.TextMuted, fontSmall, DT_LEFT|DT_WORDBREAK)
	}

	// Live AI Output Console Card
	lastQuery, lastResponse, isBusy := ai.Get().GetLastState()
	consoleTop := gridTop + cardH*2 + Scale(24)
	consoleR := RECT{Left: bounds.Left + Scale(24), Top: consoleTop, Right: bounds.Right - Scale(24), Bottom: bounds.Bottom - Scale(16)}
	DrawRoundedBox(hdc, consoleR, RGB(11, 16, 26), theme.BorderColor, Scale(10))

	headConsR := RECT{Left: consoleR.Left + Scale(14), Top: consoleR.Top + Scale(10), Right: consoleR.Right - Scale(14), Bottom: consoleR.Top + Scale(30)}
	consTitle := "🧠 AI Diagnostic Response Console"
	if isBusy {
		consTitle = "⏳ Generating AI Diagnostic Reasoning..."
	}
	DrawTextSimple(hdc, consTitle, headConsR, theme.AccentAI, fontSubhead, DT_LEFT|DT_VCENTER|DT_SINGLELINE)

	bodyConsR := RECT{Left: consoleR.Left + Scale(14), Top: consoleR.Top + Scale(34), Right: consoleR.Right - Scale(14), Bottom: consoleR.Bottom - Scale(10)}
	respText := "Click 'Run ⚡' on any Agricultural Preset Card above to execute live AI crop diagnosis, irrigation calculation, or Mandi price forecasting."
	if lastResponse != "" {
		respText = fmt.Sprintf("Query: %s\n\n%s", lastQuery, lastResponse)
	}
	DrawTextSimple(hdc, respText, bodyConsR, theme.TextBody, fontSmall, DT_LEFT|DT_WORDBREAK)
}

// RenderIoTView renders the IoT & Hardware Peripherals Hub with protocol diagnostics, device cards, and AI scheduler.
func RenderIoTView(hdc uintptr, bounds RECT, support iot.HardwareSupportMatrix, devices []iot.IoTDevice, schedules []iot.AITaskSchedule, theme FluentPalette, fontTitle, fontBody, fontSmall, fontSubhead uintptr, hitboxes *[]HitBox) {
	headerR := RECT{Left: bounds.Left + Scale(24), Top: bounds.Top + Scale(16), Right: bounds.Right - Scale(24), Bottom: bounds.Top + Scale(44)}
	DrawTextSimple(hdc, "IoT & Hardware Peripherals Hub", headerR, theme.TextTitle, fontTitle, DT_LEFT|DT_VCENTER|DT_SINGLELINE)

	subR := RECT{Left: bounds.Left + Scale(24), Top: bounds.Top + Scale(44), Right: bounds.Right - Scale(24), Bottom: bounds.Top + Scale(66)}
	DrawTextSimple(hdc, "Multi-Protocol: Wi-Fi, LAN, Bluetooth, NFC, USB  •  AI Smart Timers & Automation", subR, theme.PrimaryGreen, fontSmall, DT_LEFT|DT_VCENTER|DT_SINGLELINE)

	// Hardware Diagnostic Status Bar
	barR := RECT{Left: bounds.Left + Scale(24), Top: bounds.Top + Scale(70), Right: bounds.Right - Scale(24), Bottom: bounds.Top + Scale(102)}
	DrawRoundedBox(hdc, barR, theme.BgCard, theme.BorderColor, Scale(8))

	pillX := barR.Left + Scale(10)
	pillY := barR.Top + Scale(4)

	// 1. Wi-Fi Pill
	wifiBg := theme.BadgeOnline
	wifiText := "Wi-Fi: Active"
	if !support.WiFiSupported {
		wifiBg = theme.BadgeOffline
		wifiText = "Wi-Fi: No Adapter"
	}
	DrawBadge(hdc, wifiText, pillX, pillY, wifiBg, RGB(255, 255, 255), fontSmall)
	pillX += Scale(120)

	// 2. Bluetooth Pill
	btBg := theme.BadgeOnline
	btText := "Bluetooth: OK"
	if !support.BluetoothSupported {
		btBg = theme.BadgeOffline
		btText = "Bluetooth: Missing"
	} else if !support.BluetoothActive {
		btBg = RGB(245, 158, 11)
		btText = "Bluetooth: Disabled"
	}
	DrawBadge(hdc, btText, pillX, pillY, btBg, RGB(255, 255, 255), fontSmall)
	pillX += Scale(135)

	// 3. LAN Pill
	lanBg := theme.BadgeOnline
	lanText := "LAN: Connected"
	if !support.LANActive {
		lanBg = theme.BadgeOffline
		lanText = "LAN: Idle"
	}
	DrawBadge(hdc, lanText, pillX, pillY, lanBg, RGB(255, 255, 255), fontSmall)
	pillX += Scale(120)

	// 4. NFC Pill
	nfcBg := theme.BadgeOffline
	nfcText := "NFC: No Proximity Device"
	if support.NFCActive {
		nfcBg = theme.BadgeOnline
		nfcText = "NFC: Ready"
	}
	DrawBadge(hdc, nfcText, pillX, pillY, nfcBg, RGB(255, 255, 255), fontSmall)
	pillX += Scale(170)

	// 5. WAN Internet Pill
	netBg := RGB(245, 158, 11)
	netText := "WAN Internet: OFF (Air-Gapped)"
	if support.InternetModeEnabled {
		netBg = theme.BadgeOnline
		netText = "WAN Internet: ON"
	}
	DrawBadge(hdc, netText, pillX, pillY, netBg, RGB(255, 255, 255), fontSmall)

	// Connected Devices Section (Grid)
	gridTop := bounds.Top + Scale(110)
	cardW := (bounds.Right - bounds.Left - Scale(72)) / 3
	cardH := Scale(130)

	for i, dev := range devices {
		if i >= 6 {
			break
		}
		col := i % 3
		row := i / 3
		left := bounds.Left + Scale(24) + int32(col)*(cardW+Scale(12))
		top := gridTop + int32(row)*(cardH+Scale(10))
		cardR := RECT{Left: left, Top: top, Right: left + cardW, Bottom: top + cardH}

		DrawRoundedBox(hdc, cardR, theme.BgCard, theme.BorderColor, Scale(8))

		// Header: Name & Protocol
		nameR := RECT{Left: cardR.Left + Scale(12), Top: cardR.Top + Scale(8), Right: cardR.Right - Scale(12), Bottom: cardR.Top + Scale(26)}
		DrawTextSimple(hdc, dev.Name, nameR, theme.TextTitle, fontBody, DT_LEFT|DT_VCENTER|DT_SINGLELINE|DT_END_ELLIPSIS)

		protoR := RECT{Left: cardR.Left + Scale(12), Top: cardR.Top + Scale(26), Right: cardR.Right - Scale(12), Bottom: cardR.Top + Scale(42)}
		DrawTextSimple(hdc, fmt.Sprintf("%s • %s", dev.Protocol, dev.Address), protoR, theme.TextMuted, fontSmall, DT_LEFT|DT_VCENTER|DT_SINGLELINE|DT_END_ELLIPSIS)

		// State Details
		stateR := RECT{Left: cardR.Left + Scale(12), Top: cardR.Top + Scale(44), Right: cardR.Right - Scale(12), Bottom: cardR.Top + Scale(88)}
		var stateText string
		switch dev.Type {
		case iot.TypeRelay:
			pwr, _ := dev.State["power"].(bool)
			if pwr {
				stateText = "Power: [ ON ]  •  Flow: 45 L/min\nLoad: 8.4A @ 228V (Pump Active)"
			} else {
				stateText = "Power: [ OFF ]  •  Motor Idle\nVoltage: 228V (Ready)"
			}
		case iot.TypeSensor:
			moist, _ := dev.State["moisture_pct"].(float64)
			temp, _ := dev.State["temp_c"].(float64)
			bat, _ := dev.State["battery_pct"].(int)
			stateText = fmt.Sprintf("Moisture: %.1f%%  •  Temp: %.1f°C\nBattery: %d%% (Telemetry Sync OK)", moist, temp, bat)
		case iot.TypePrinter:
			jobs, _ := dev.State["jobs_queued"].(int)
			stateText = fmt.Sprintf("Paper Status: Ready (ESC/POS)\nPrint Queue: %d pending jobs", jobs)
		case iot.TypeAudio:
			bat, _ := dev.State["battery_pct"].(int)
			stateText = fmt.Sprintf("Audio Sink: Active (AAC)\nBattery: %d%% • Low Latency", bat)
		case iot.TypeScanner:
			res, _ := dev.State["resolution"].(string)
			stateText = fmt.Sprintf("Resolution: %s\nReady for Document OCR Scan", res)
		default:
			stateText = "Device Status: Connected & Online"
		}
		DrawTextSimple(hdc, stateText, stateR, theme.TextBody, fontSmall, DT_LEFT|DT_WORDBREAK)

		// Bottom Action Button
		btnActionR := RECT{Left: cardR.Left + Scale(12), Top: cardR.Bottom - Scale(34), Right: cardR.Right - Scale(12), Bottom: cardR.Bottom - Scale(8)}
		switch dev.Type {
		case iot.TypeRelay:
			pwr, _ := dev.State["power"].(bool)
			btnBg := theme.PrimaryGreen
			btnLabel := "Turn Pump ON"
			if pwr {
				btnBg = RGB(239, 68, 68)
				btnLabel = "Turn Pump OFF"
			}
			DrawRoundedBox(hdc, btnActionR, btnBg, btnBg, Scale(6))
			DrawTextSimple(hdc, btnLabel, btnActionR, RGB(255, 255, 255), fontSmall, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
			*hitboxes = append(*hitboxes, HitBox{Key: fmt.Sprintf("IOT_TOGGLE_%s", dev.ID), Rect: btnActionR})

		case iot.TypePrinter:
			DrawRoundedBox(hdc, btnActionR, theme.AccentCCTV, theme.AccentCCTV, Scale(6))
			DrawTextSimple(hdc, "Test Print Receipt", btnActionR, RGB(255, 255, 255), fontSmall, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
			*hitboxes = append(*hitboxes, HitBox{Key: fmt.Sprintf("IOT_PRINT_%s", dev.ID), Rect: btnActionR})

		case iot.TypeScanner:
			DrawRoundedBox(hdc, btnActionR, theme.AccentAI, theme.AccentAI, Scale(6))
			DrawTextSimple(hdc, "Scan Document", btnActionR, RGB(255, 255, 255), fontSmall, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
			*hitboxes = append(*hitboxes, HitBox{Key: fmt.Sprintf("IOT_SCAN_%s", dev.ID), Rect: btnActionR})

		case iot.TypeSensor:
			DrawRoundedBox(hdc, btnActionR, theme.BgCardHover, theme.BorderColor, Scale(6))
			DrawTextSimple(hdc, "Poll Sensor Data", btnActionR, theme.TextTitle, fontSmall, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
			*hitboxes = append(*hitboxes, HitBox{Key: fmt.Sprintf("IOT_POLL_%s", dev.ID), Rect: btnActionR})

		default:
			DrawRoundedBox(hdc, btnActionR, theme.BgCardHover, theme.BorderColor, Scale(6))
			DrawTextSimple(hdc, "Device Options", btnActionR, theme.TextBody, fontSmall, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
		}
	}

	// Bottom AI Automation & Scheduler Panel
	schedTop := gridTop + Scale(130)*2 + Scale(16)
	schedR := RECT{Left: bounds.Left + Scale(24), Top: schedTop, Right: bounds.Right - Scale(24), Bottom: bounds.Bottom - Scale(14)}
	DrawRoundedBox(hdc, schedR, theme.BgCard, theme.BorderColor, Scale(10))

	schedTitleR := RECT{Left: schedR.Left + Scale(16), Top: schedR.Top + Scale(8), Right: schedR.Right - Scale(16), Bottom: schedR.Top + Scale(28)}
	DrawTextSimple(hdc, "AI Hardware Automation & Schedule Timers", schedTitleR, theme.AccentAI, fontSubhead, DT_LEFT|DT_VCENTER|DT_SINGLELINE)

	// List active timers
	schedY := schedR.Top + Scale(30)
	for i, s := range schedules {
		if i >= 2 {
			break
		}
		itemR := RECT{Left: schedR.Left + Scale(16), Top: schedY, Right: schedR.Right - Scale(140), Bottom: schedY + Scale(20)}
		itemText := fmt.Sprintf("• %s (%s) — Trigger: %s (Duration: %d mins)", s.DeviceName, s.Action, s.AIPromptTrigger, s.DurationMinutes)
		DrawTextSimple(hdc, itemText, itemR, theme.TextBody, fontSmall, DT_LEFT|DT_VCENTER|DT_SINGLELINE|DT_END_ELLIPSIS)
		schedY += Scale(22)
	}

	// Add AI Schedule Button
	btnSchedR := RECT{Left: schedR.Right - Scale(180), Top: schedR.Top + Scale(8), Right: schedR.Right - Scale(16), Bottom: schedR.Top + Scale(38)}
	DrawRoundedBox(hdc, btnSchedR, theme.AccentAI, theme.AccentAI, Scale(6))
	DrawTextSimple(hdc, "+ New AI Schedule", btnSchedR, RGB(255, 255, 255), fontSmall, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
	*hitboxes = append(*hitboxes, HitBox{Key: "IOT_ADD_AI_SCHEDULE", Rect: btnSchedR})
}

// RenderLogsView renders activity logs and real-time transfer progress bars.
func RenderLogsView(hdc uintptr, bounds RECT, transfers []models.TransferProgress, logs []string, theme FluentPalette, fontTitle, fontBody, fontSmall, fontSubhead uintptr, hitboxes *[]HitBox) {
	headerR := RECT{Left: bounds.Left + Scale(24), Top: bounds.Top + Scale(18), Right: bounds.Right - Scale(24), Bottom: bounds.Top + Scale(48)}
	DrawTextSimple(hdc, "Transfers & Activity Logs", headerR, theme.TextTitle, fontTitle, DT_LEFT|DT_VCENTER|DT_SINGLELINE)

	// Clear Logs button
	btnClearR := RECT{Left: bounds.Right - Scale(140), Top: bounds.Top + Scale(16), Right: bounds.Right - Scale(24), Bottom: bounds.Top + Scale(48)}
	DrawRoundedBox(hdc, btnClearR, theme.BgCard, theme.BorderColor, Scale(6))
	DrawTextSimple(hdc, "Clear Logs", btnClearR, theme.TextTitle, fontSmall, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
	*hitboxes = append(*hitboxes, HitBox{Key: "BTN_CLEAR_LOGS", Rect: btnClearR})

	// Active Transfers
	transTop := bounds.Top + Scale(65)
	if len(transfers) > 0 {
		for i, t := range transfers {
			if i >= 2 {
				break
			}
			tR := RECT{Left: bounds.Left + Scale(24), Top: transTop, Right: bounds.Right - Scale(24), Bottom: transTop + Scale(60)}
			DrawRoundedBox(hdc, tR, theme.BgCard, theme.BorderColor, Scale(8))

			infoR := RECT{Left: tR.Left + Scale(14), Top: tR.Top + Scale(6), Right: tR.Right - Scale(14), Bottom: tR.Top + Scale(26)}
			infoText := fmt.Sprintf("%s  •  %.1f MB / %.1f MB (%.1f MB/s)", t.FileName, float64(t.BytesSent)/(1024*1024), float64(t.BytesTotal)/(1024*1024), t.SpeedMBps)
			DrawTextSimple(hdc, infoText, infoR, theme.TextTitle, fontSmall, DT_LEFT|DT_VCENTER|DT_SINGLELINE)

			progR := RECT{Left: tR.Left + Scale(14), Top: tR.Top + Scale(32), Right: tR.Right - Scale(14), Bottom: tR.Top + Scale(44)}
			pct := 0.0
			if t.BytesTotal > 0 {
				pct = float64(t.BytesSent) / float64(t.BytesTotal)
			}
			DrawProgressBar(hdc, progR, pct, theme.PrimaryGreen, theme.BgCardHover)

			transTop += Scale(68)
		}
	}

	// Logs Console Card
	logCardR := RECT{Left: bounds.Left + Scale(24), Top: transTop + Scale(10), Right: bounds.Right - Scale(24), Bottom: bounds.Bottom - Scale(16)}
	DrawRoundedBox(hdc, logCardR, RGB(10, 14, 22), theme.BorderColor, Scale(10))

	logY := logCardR.Top + Scale(12)
	start := len(logs) - 1
	for i := start; i >= 0 && logY < logCardR.Bottom-Scale(20); i-- {
		line := logs[i]
		lineR := RECT{Left: logCardR.Left + Scale(14), Top: logY, Right: logCardR.Right - Scale(14), Bottom: logY + Scale(18)}
		DrawTextSimple(hdc, line, lineR, theme.TextBody, fontSmall, DT_LEFT|DT_VCENTER|DT_SINGLELINE|DT_END_ELLIPSIS)
		logY += Scale(20)
	}
}

// RenderSettingsView renders configuration, theme toggle, and NearMitra branding footer matching mobile app.
func RenderSettingsView(hdc uintptr, bounds RECT, cfg config.AppConfig, isDark bool, theme FluentPalette, fontTitle, fontBody, fontSmall, fontSubhead uintptr, hitboxes *[]HitBox) {
	headerR := RECT{Left: bounds.Left + Scale(24), Top: bounds.Top + Scale(16), Right: bounds.Right - Scale(24), Bottom: bounds.Top + Scale(44)}
	DrawTextSimple(hdc, "Settings & About NearMitra", headerR, theme.TextTitle, fontTitle, DT_LEFT|DT_VCENTER|DT_SINGLELINE)

	// Configuration Card
	cfgR := RECT{Left: bounds.Left + Scale(24), Top: bounds.Top + Scale(52), Right: bounds.Right - Scale(24), Bottom: bounds.Top + Scale(190)}
	DrawRoundedBox(hdc, cfgR, theme.BgCard, theme.BorderColor, Scale(10))

	// Save Folder
	saveLblR := RECT{Left: cfgR.Left + Scale(20), Top: cfgR.Top + Scale(12), Right: cfgR.Right - Scale(20), Bottom: cfgR.Top + Scale(28)}
	DrawTextSimple(hdc, "Download / Transfer Save Directory:", saveLblR, theme.TextMuted, fontSmall, DT_LEFT|DT_VCENTER|DT_SINGLELINE)

	savePathR := RECT{Left: cfgR.Left + Scale(20), Top: cfgR.Top + Scale(32), Right: cfgR.Right - Scale(180), Bottom: cfgR.Top + Scale(64)}
	DrawRoundedBox(hdc, savePathR, theme.BgMain, theme.BorderColor, Scale(6))
	DrawTextSimple(hdc, cfg.SaveDirectory, RECT{Left: savePathR.Left + Scale(10), Top: savePathR.Top, Right: savePathR.Right - Scale(10), Bottom: savePathR.Bottom}, theme.TextTitle, fontSmall, DT_LEFT|DT_VCENTER|DT_SINGLELINE|DT_END_ELLIPSIS)

	btnBrowseR := RECT{Left: cfgR.Right - Scale(160), Top: cfgR.Top + Scale(32), Right: cfgR.Right - Scale(20), Bottom: cfgR.Top + Scale(64)}
	DrawRoundedBox(hdc, btnBrowseR, theme.PrimaryGreen, theme.PrimaryGreen, Scale(6))
	DrawTextSimple(hdc, "Open Folder 📂", btnBrowseR, RGB(255, 255, 255), fontSmall, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
	*hitboxes = append(*hitboxes, HitBox{Key: "BTN_OPEN_SAVE_DIR", Rect: btnBrowseR})

	// Theme switch
	themeLblR := RECT{Left: cfgR.Left + Scale(20), Top: cfgR.Top + Scale(76), Right: cfgR.Right - Scale(20), Bottom: cfgR.Top + Scale(94)}
	DrawTextSimple(hdc, "Application Theme Appearance:", themeLblR, theme.TextMuted, fontSmall, DT_LEFT|DT_VCENTER|DT_SINGLELINE)

	themeModeText := "🌙 Switch to Light Mode"
	if !isDark {
		themeModeText = "☀️ Switch to Dark Mode"
	}
	btnThemeR := RECT{Left: cfgR.Left + Scale(20), Top: cfgR.Top + Scale(98), Right: cfgR.Left + Scale(220), Bottom: cfgR.Top + Scale(130)}
	DrawRoundedBox(hdc, btnThemeR, theme.BgCardHover, theme.BorderColor, Scale(6))
	DrawTextSimple(hdc, themeModeText, btnThemeR, theme.TextTitle, fontSmall, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
	*hitboxes = append(*hitboxes, HitBox{Key: "BTN_TOGGLE_THEME", Rect: btnThemeR})

	// Comprehensive About NearMitra Brand Card (Parity with Mobile Readme / About)
	aboutR := RECT{Left: bounds.Left + Scale(24), Top: bounds.Top + Scale(200), Right: bounds.Right - Scale(24), Bottom: bounds.Bottom - Scale(14)}
	DrawRoundedBox(hdc, aboutR, theme.BgCard, theme.BorderColor, Scale(10))

	appTitleR := RECT{Left: aboutR.Left + Scale(20), Top: aboutR.Top + Scale(12), Right: aboutR.Right - Scale(20), Bottom: aboutR.Top + Scale(34)}
	DrawTextSimple(hdc, "NearMitra Ecosystem • Mobile & Windows Desktop Suite", appTitleR, theme.PrimaryGreen, fontSubhead, DT_LEFT|DT_VCENTER|DT_SINGLELINE)

	badgeRowY := aboutR.Top + Scale(38)
	DrawBadge(hdc, "⚡ 50+ MB/s Zero-Data P2P", aboutR.Left+Scale(20), badgeRowY, RGB(16, 185, 129), RGB(255, 255, 255), fontSmall)
	DrawBadge(hdc, "📹 Live CCTV AI Surveillance", aboutR.Left+Scale(210), badgeRowY, RGB(59, 130, 246), RGB(255, 255, 255), fontSmall)
	DrawBadge(hdc, "🧠 Dual-Tier LLM Mesh", aboutR.Left+Scale(420), badgeRowY, RGB(139, 92, 246), RGB(255, 255, 255), fontSmall)
	DrawBadge(hdc, "🔌 Multi-Protocol IoT Hub", aboutR.Left+Scale(590), badgeRowY, RGB(245, 158, 11), RGB(255, 255, 255), fontSmall)

	descR := RECT{Left: aboutR.Left + Scale(20), Top: badgeRowY + Scale(32), Right: aboutR.Right - Scale(20), Bottom: aboutR.Bottom - Scale(44)}
	descContent := "NearMitra connects Windows PCs, laptops, and Android smartphones over zero-configuration local Wi-Fi and hotspot. Supports ultra-fast P2P file transfers, emoji-rich chat, live CCTV monitoring, IoT smart automation, and dual-tier AI compute sharing.\n\n" +
		"• Architecture: Zero-Config Multicast UDP 43888 Discovery + High-Speed TCP 43889 Chunks (AES-GCM)\n" +
		"• Computer Vision: Live Motion Detection, Crop Disease Leaf Health Diagnostics, Night Vision IR Boost\n" +
		"• Peripherals: Mandi Thermal Gate Pass Printers (ESC/POS), Soil Moisture Sensors, Irrigation Relays"
	DrawTextSimple(hdc, descContent, descR, theme.TextBody, fontSmall, DT_LEFT|DT_WORDBREAK)

	// Separator line
	sepR := RECT{Left: aboutR.Left + Scale(20), Top: aboutR.Bottom - Scale(34), Right: aboutR.Right - Scale(20), Bottom: aboutR.Bottom - Scale(33)}
	DrawRoundedBox(hdc, sepR, theme.BorderColor, theme.BorderColor, 0)

	footerR := RECT{Left: aboutR.Left + Scale(20), Top: aboutR.Bottom - Scale(30), Right: aboutR.Right - Scale(20), Bottom: aboutR.Bottom - Scale(8)}
	DrawTextSimple(hdc, "Made with ❤️ for Indian Farmers & High-Speed P2P Mesh  •  NearMitra Ecosystem v2.0", footerR, theme.TextMuted, fontSmall, DT_CENTER|DT_VCENTER|DT_SINGLELINE)
}
