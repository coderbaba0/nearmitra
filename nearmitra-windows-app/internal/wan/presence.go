package wan

import "time"

const presenceHeartbeatInterval = 20 * time.Second
const desktopPresenceLease = 75 * time.Second

func presenceLease(platform string, declared int64) time.Duration {
	if declared > 0 {
		if declared < 30000 {
			declared = 30000
		}
		if declared > 120000 {
			declared = 120000
		}
		return time.Duration(declared) * time.Millisecond
	}
	if platform == "windows" {
		return desktopPresenceLease
	}
	return 0 // SDK peers use Firebase onDisconnect instead of a heartbeat lease.
}

func presenceAlive(online bool, platform string, lastSeen time.Time, declared int64, now time.Time) bool {
	if !online {
		return false
	}
	ttl := presenceLease(platform, declared)
	if ttl == 0 {
		return true
	}
	if lastSeen.IsZero() {
		return false
	}
	age := now.Sub(lastSeen)
	return age >= -15*time.Second && age < ttl
}

func presenceNumber(value interface{}) int64 {
	switch v := value.(type) {
	case float64:
		return int64(v)
	case int64:
		return v
	case int:
		return int64(v)
	default:
		return 0
	}
}
