package ai

import "nearmitra-windows-app/internal/models"

// PeerAllowed checks device IDs first-class; revocation overrides any older alias grant.
func PeerAllowed(cfg models.AIConfig, identities ...string) bool {
	matches := func(entries []string) bool {
		for _, entry := range entries {
			for _, id := range identities {
				if id != "" && entry == id {
					return true
				}
			}
		}
		return false
	}
	return !matches(cfg.RevokedPeers) && matches(cfg.AllowedPeers)
}

func SharedAccess(cfg models.AIConfig, identities ...string) (bool, string) {
	if !cfg.Enabled {
		return false, "AI is disabled on this desktop."
	}
	if !cfg.ShareAI {
		return false, "Nearby AI sharing is disabled on this desktop."
	}
	if !PeerAllowed(cfg, identities...) {
		return false, "Nearby AI access has not been granted by this desktop."
	}
	return true, ""
}
