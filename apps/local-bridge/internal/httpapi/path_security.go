package httpapi

import (
	"fmt"
	"os"
	"path"
	"path/filepath"
	"strings"
)

func bridgeSafeJoinUnderRoot(root string, elems ...string) (string, error) {
	root = filepath.Clean(strings.TrimSpace(root))
	if root == "" || root == "." {
		return "", fmt.Errorf("root path is required")
	}
	target := filepath.Join(append([]string{root}, elems...)...)
	absRoot, err := filepath.Abs(root)
	if err != nil {
		return "", err
	}
	absTarget, err := filepath.Abs(target)
	if err != nil {
		return "", err
	}
	rel, err := filepath.Rel(absRoot, absTarget)
	if err != nil {
		return "", err
	}
	if rel == "." || rel == "" {
		return absTarget, nil
	}
	if strings.HasPrefix(rel, ".."+string(filepath.Separator)) || rel == ".." || filepath.IsAbs(rel) {
		return "", fmt.Errorf("path escapes root")
	}
	return absTarget, nil
}

func bridgeCleanRelativePath(value string) (string, bool) {
	cleaned := path.Clean(strings.TrimSpace(value))
	if cleaned == "" || cleaned == "." || cleaned == ".." || strings.HasPrefix(cleaned, "../") || path.IsAbs(cleaned) {
		return "", false
	}
	return cleaned, true
}

func bridgeReadRegularFileUnderRoot(root string, relativePath string) ([]byte, error) {
	relativePath, ok := bridgeCleanRelativePath(relativePath)
	if !ok {
		return nil, fmt.Errorf("invalid relative path")
	}
	filePath, err := bridgeSafeJoinUnderRoot(root, filepath.FromSlash(relativePath))
	if err != nil {
		return nil, err
	}
	info, err := os.Lstat(filePath)
	if err != nil {
		return nil, err
	}
	if info.IsDir() || info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() {
		return nil, fmt.Errorf("not a regular file")
	}
	return os.ReadFile(filePath) // #nosec G304 -- path is constrained to root and symlinks are rejected above.
}
