package main

import (
	"bytes"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
)

type InstallOptions struct {
	DesktopShortcut bool `json:"desktop_shortcut"`
	StartMenu       bool `json:"start_menu"`
	Autostart       bool `json:"autostart"`
	PrivateNetwork  bool `json:"private_network"`
}

func writeInstallFiles(dir string) error {
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}
	files := map[string][]byte{"NearMitra.exe": appBinary, "nearmitra.ico": appIcon}
	if !bytes.HasPrefix(appBinary, []byte("MZ")) {
		return fmt.Errorf("setup payload is not a Windows executable")
	}
	for name, data := range files {
		path := filepath.Join(dir, name)
		tmp := path + ".installing"
		if err := os.WriteFile(tmp, data, 0644); err != nil {
			return err
		}
		if err := os.Rename(tmp, path); err != nil {
			_ = os.Remove(tmp)
			return fmt.Errorf("cannot update %s; close NearMitra and retry: %w", name, err)
		}
	}
	self, err := os.Executable()
	if err != nil {
		return err
	}
	uninstaller, err := os.ReadFile(self)
	if err != nil {
		return err
	}
	if err = os.WriteFile(filepath.Join(dir, "Uninstall.exe"), uninstaller, 0644); err != nil {
		return err
	}
	return fs.WalkDir(assetsFS, "assets", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		rel, err := filepath.Rel("assets", path)
		if err != nil {
			return err
		}
		target := filepath.Join(dir, "assets", rel)
		if err = os.MkdirAll(filepath.Dir(target), 0755); err != nil {
			return err
		}
		data, err := assetsFS.ReadFile(path)
		if err != nil {
			return err
		}
		return os.WriteFile(target, data, 0644)
	})
}
