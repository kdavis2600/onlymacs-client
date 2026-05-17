package httpapi

import (
	"encoding/xml"
	"io"
	"os"
	"path/filepath"
	"strings"
)

var clientBuildInfoPlistCandidates = defaultClientBuildInfoPlistCandidates

func clientBuildFromEnv() *clientBuild {
	envBuild := normalizeClientBuild(&clientBuild{
		Product:        os.Getenv("ONLYMACS_CLIENT_PRODUCT"),
		Version:        os.Getenv("ONLYMACS_CLIENT_VERSION"),
		BuildNumber:    os.Getenv("ONLYMACS_CLIENT_BUILD_NUMBER"),
		BuildTimestamp: os.Getenv("ONLYMACS_CLIENT_BUILD_TIMESTAMP"),
		Channel:        os.Getenv("ONLYMACS_CLIENT_BUILD_CHANNEL"),
	})
	bundleBuild := clientBuildFromContainingAppBundle()
	return mergeClientBuild(envBuild, bundleBuild)
}

func normalizeClientBuild(build *clientBuild) *clientBuild {
	if build == nil {
		return nil
	}
	normalized := *build
	normalized.Product = compactClientBuildString(normalized.Product)
	normalized.Version = compactClientBuildString(normalized.Version)
	normalized.BuildNumber = compactClientBuildString(normalized.BuildNumber)
	normalized.BuildTimestamp = compactClientBuildString(normalized.BuildTimestamp)
	normalized.Channel = compactClientBuildString(normalized.Channel)
	if normalized.Product == "" &&
		normalized.Version == "" &&
		normalized.BuildNumber == "" &&
		normalized.BuildTimestamp == "" &&
		normalized.Channel == "" {
		return nil
	}
	return &normalized
}

func compactClientBuildString(value string) string {
	return strings.Join(strings.Fields(strings.TrimSpace(value)), " ")
}

func mergeClientBuild(primary *clientBuild, fallback *clientBuild) *clientBuild {
	if primary == nil {
		return fallback
	}
	if fallback == nil {
		return primary
	}
	merged := *primary
	if merged.Product == "" {
		merged.Product = fallback.Product
	}
	if merged.Version == "" {
		merged.Version = fallback.Version
	}
	if merged.BuildNumber == "" {
		merged.BuildNumber = fallback.BuildNumber
	}
	if merged.BuildTimestamp == "" {
		merged.BuildTimestamp = fallback.BuildTimestamp
	}
	if merged.Channel == "" {
		merged.Channel = fallback.Channel
	}
	return normalizeClientBuild(&merged)
}

func clientBuildFromContainingAppBundle() *clientBuild {
	for _, path := range clientBuildInfoPlistCandidates() {
		if build := clientBuildFromInfoPlist(path); build != nil {
			return build
		}
	}
	return nil
}

func defaultClientBuildInfoPlistCandidates() []string {
	executablePath, err := os.Executable()
	if err != nil {
		return nil
	}

	executablePaths := []string{executablePath}
	if resolvedPath, err := filepath.EvalSymlinks(executablePath); err == nil && resolvedPath != executablePath {
		executablePaths = append(executablePaths, resolvedPath)
	}

	seen := make(map[string]struct{})
	var candidates []string
	for _, executablePath := range executablePaths {
		dir := filepath.Dir(executablePath)
		for depth := 0; depth < 8; depth++ {
			if filepath.Base(dir) == "Contents" {
				candidate := filepath.Join(dir, "Info.plist")
				if _, ok := seen[candidate]; !ok {
					seen[candidate] = struct{}{}
					candidates = append(candidates, candidate)
				}
			}
			if strings.HasSuffix(filepath.Base(dir), ".app") {
				candidate := filepath.Join(dir, "Contents", "Info.plist")
				if _, ok := seen[candidate]; !ok {
					seen[candidate] = struct{}{}
					candidates = append(candidates, candidate)
				}
			}
			parent := filepath.Dir(dir)
			if parent == dir {
				break
			}
			dir = parent
		}
	}
	return candidates
}

func clientBuildFromInfoPlist(path string) *clientBuild {
	values, err := readInfoPlistStrings(path)
	if err != nil {
		return nil
	}
	return normalizeClientBuild(&clientBuild{
		Product:        defaultValue(values["CFBundleName"], "OnlyMacs"),
		Version:        values["CFBundleShortVersionString"],
		BuildNumber:    values["CFBundleVersion"],
		BuildTimestamp: values["OnlyMacsBuildTimestamp"],
		Channel:        values["OnlyMacsBuildChannel"],
	})
}

func readInfoPlistStrings(path string) (map[string]string, error) {
	file, err := os.Open(path) // #nosec G304 -- Info.plist paths come from known app bundle candidates.
	if err != nil {
		return nil, err
	}
	defer file.Close()

	decoder := xml.NewDecoder(file)
	values := make(map[string]string)
	var currentKey string
	for {
		token, err := decoder.Token()
		if err != nil {
			if err == io.EOF {
				return values, nil
			}
			return nil, err
		}
		start, ok := token.(xml.StartElement)
		if !ok {
			continue
		}
		switch start.Name.Local {
		case "key":
			var key string
			if err := decoder.DecodeElement(&key, &start); err != nil {
				return nil, err
			}
			currentKey = strings.TrimSpace(key)
		case "string":
			var value string
			if err := decoder.DecodeElement(&value, &start); err != nil {
				return nil, err
			}
			if currentKey != "" {
				values[currentKey] = compactClientBuildString(value)
				currentKey = ""
			}
		default:
			currentKey = ""
		}
	}
}
