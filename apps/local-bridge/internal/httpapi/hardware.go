package httpapi

import (
	"os"
	"os/exec"
	"runtime"
	"strconv"
	"strings"
)

var currentHardwareProfile = localHardwareProfile

func localHardwareProfile() *hardwareProfile {
	if runtime.GOOS == "linux" {
		return linuxHardwareProfile()
	}

	profile := &hardwareProfile{}

	if cpuBrand := sysctlString("machdep.cpu.brand_string"); cpuBrand != "" {
		profile.CPUBrand = compactCPUBrand(cpuBrand)
	}
	if memoryBytes := sysctlUint64("hw.memsize"); memoryBytes > 0 {
		profile.MemoryGB = roundedMemoryGB(memoryBytes)
	}

	if profile.CPUBrand == "" && profile.MemoryGB == 0 {
		return nil
	}

	return profile
}

func linuxHardwareProfile() *hardwareProfile {
	profile := &hardwareProfile{}

	if cpuInfo, err := os.ReadFile("/proc/cpuinfo"); err == nil {
		for _, line := range strings.Split(string(cpuInfo), "\n") {
			key, value, ok := strings.Cut(line, ":")
			if !ok {
				continue
			}
			switch strings.TrimSpace(strings.ToLower(key)) {
			case "model name", "hardware", "processor":
				if cpuBrand := compactCPUBrand(value); cpuBrand != "" {
					profile.CPUBrand = cpuBrand
				}
			}
			if profile.CPUBrand != "" {
				break
			}
		}
	}

	if memInfo, err := os.ReadFile("/proc/meminfo"); err == nil {
		for _, line := range strings.Split(string(memInfo), "\n") {
			key, value, ok := strings.Cut(line, ":")
			if !ok || strings.TrimSpace(key) != "MemTotal" {
				continue
			}
			fields := strings.Fields(value)
			if len(fields) == 0 {
				break
			}
			memKiB, err := strconv.ParseUint(fields[0], 10, 64)
			if err == nil {
				profile.MemoryGB = roundedMemoryGB(memKiB * 1024)
			}
			break
		}
	}

	if profile.CPUBrand == "" && profile.MemoryGB == 0 {
		return nil
	}
	return profile
}

func compactCPUBrand(cpuBrand string) string {
	compact := strings.Join(strings.Fields(strings.TrimSpace(cpuBrand)), " ")
	compact = strings.TrimPrefix(compact, "Apple ")
	return compact
}

func sysctlString(key string) string {
	switch key {
	case "machdep.cpu.brand_string", "hw.memsize":
	default:
		return ""
	}
	output, err := exec.Command("sysctl", "-n", key).Output() // #nosec G204 -- key is restricted to the allowlist above.
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(output))
}

func sysctlUint64(key string) uint64 {
	value := sysctlString(key)
	if value == "" {
		return 0
	}
	parsed, err := strconv.ParseUint(value, 10, 64)
	if err != nil {
		return 0
	}
	return parsed
}

func roundedMemoryGB(memoryBytes uint64) int {
	const gibibyte = uint64(1024 * 1024 * 1024)
	if memoryBytes == 0 {
		return 0
	}
	rounded := (memoryBytes + (gibibyte / 2)) / gibibyte
	maxInt := uint64(^uint(0) >> 1)
	if rounded > maxInt {
		return int(maxInt)
	}
	return int(rounded)
}
