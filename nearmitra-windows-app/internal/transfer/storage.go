package transfer

import (
	"archive/zip"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// StoreReceivedFile commits a complete transfer before making it visible in chat.
func StoreReceivedFile(dir, name string, folder bool, input io.Reader, size int64) (string, error) {
	if size < 0 {
		return "", fmt.Errorf("invalid file size")
	}
	name = filepath.Base(strings.ReplaceAll(name, "\\", "/"))
	if name == "" || name == "." || name == ".." {
		return "", fmt.Errorf("invalid file name")
	}
	if err := os.MkdirAll(dir, 0755); err != nil {
		return "", err
	}
	staged, err := os.CreateTemp(dir, ".receive-*.part")
	if err != nil {
		return "", err
	}
	defer os.Remove(staged.Name())
	_, copyErr := io.CopyN(staged, input, size)
	syncErr := staged.Sync()
	closeErr := staged.Close()
	if copyErr != nil {
		return "", fmt.Errorf("incomplete transfer: %w", copyErr)
	}
	if syncErr != nil {
		return "", syncErr
	}
	if closeErr != nil {
		return "", closeErr
	}
	if folder {
		base := strings.TrimSuffix(name, ".zip")
		dest, err := os.MkdirTemp(dir, ".folder-*")
		if err != nil {
			return "", err
		}
		defer os.RemoveAll(dest)
		if err := extractZip(staged.Name(), dest); err != nil {
			return "", err
		}
		target := uniquePath(dir, base)
		if err := os.Rename(dest, target); err != nil {
			return "", err
		}
		return target, nil
	}
	target := uniquePath(dir, name)
	// Reserve the destination atomically, so concurrent same-name transfers never overwrite.
	for {
		out, err := os.OpenFile(target, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0644)
		if os.IsExist(err) {
			target = uniquePath(dir, name)
			continue
		}
		if err != nil {
			return "", err
		}
		in, err := os.Open(staged.Name())
		if err != nil {
			out.Close()
			os.Remove(target)
			return "", err
		}
		_, err = io.Copy(out, in)
		in.Close()
		closeErr := out.Close()
		if err == nil {
			err = closeErr
		}
		if err != nil {
			os.Remove(target)
			return "", err
		}
		return target, nil
	}
}

func uniquePath(dir, name string) string {
	candidate := filepath.Join(dir, name)
	ext := filepath.Ext(name)
	base := strings.TrimSuffix(name, ext)
	for i := 1; ; i++ {
		if _, err := os.Stat(candidate); err != nil {
			return candidate
		}
		candidate = filepath.Join(dir, fmt.Sprintf("%s (%d)%s", base, i, ext))
	}
}

func extractZip(src, dest string) error {
	reader, err := zip.OpenReader(src)
	if err != nil {
		return err
	}
	defer reader.Close()
	for _, entry := range reader.File {
		path := filepath.Join(dest, filepath.FromSlash(strings.ReplaceAll(entry.Name, "\\", "/")))
		rel, err := filepath.Rel(dest, path)
		if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(os.PathSeparator)) || entry.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("invalid archive path: %s", entry.Name)
		}
		if entry.FileInfo().IsDir() {
			if err := os.MkdirAll(path, 0755); err != nil {
				return err
			}
			continue
		}
		if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
			return err
		}
		src, err := entry.Open()
		if err != nil {
			return err
		}
		dst, err := os.OpenFile(path, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0644)
		if err != nil {
			src.Close()
			return err
		}
		_, copyErr := io.Copy(dst, src)
		src.Close()
		closeErr := dst.Close()
		if copyErr != nil {
			return copyErr
		}
		if closeErr != nil {
			return closeErr
		}
	}
	return nil
}
