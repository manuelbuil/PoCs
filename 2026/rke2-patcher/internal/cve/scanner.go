package cve

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"sort"
	"strings"
)

type Result struct {
	Tool string
	CVEs []string
}

func ListForImage(image string) (Result, error) {
	if _, err := exec.LookPath("trivy"); err == nil {
		cves, scanErr := trivyCVEs(image)
		if scanErr == nil {
			return Result{Tool: "trivy", CVEs: cves}, nil
		}
	}

	if _, err := exec.LookPath("grype"); err == nil {
		cves, scanErr := grypeCVEs(image)
		if scanErr == nil {
			return Result{Tool: "grype", CVEs: cves}, nil
		}
	}

	return Result{}, fmt.Errorf("no scanner available: install trivy or grype")
}

func trivyCVEs(image string) ([]string, error) {
	cmd := exec.Command("trivy", "image", "--quiet", "--format", "json", image)
	output, err := cmd.Output()
	if err != nil {
		return nil, err
	}

	var report struct {
		Results []struct {
			Vulnerabilities []struct {
				VulnerabilityID string `json:"VulnerabilityID"`
			} `json:"Vulnerabilities"`
		} `json:"Results"`
	}

	if err := json.Unmarshal(output, &report); err != nil {
		return nil, err
	}

	return dedupeCVEs(func(appendCVE func(string)) {
		for _, result := range report.Results {
			for _, vulnerability := range result.Vulnerabilities {
				appendCVE(vulnerability.VulnerabilityID)
			}
		}
	}), nil
}

func grypeCVEs(image string) ([]string, error) {
	cmd := exec.Command("grype", image, "-o", "json")
	output, err := cmd.Output()
	if err != nil {
		return nil, err
	}

	var report struct {
		Matches []struct {
			Vulnerability struct {
				ID string `json:"id"`
			} `json:"vulnerability"`
		} `json:"matches"`
	}

	if err := json.Unmarshal(output, &report); err != nil {
		return nil, err
	}

	return dedupeCVEs(func(appendCVE func(string)) {
		for _, match := range report.Matches {
			appendCVE(match.Vulnerability.ID)
		}
	}), nil
}

func dedupeCVEs(visitor func(func(string))) []string {
	set := make(map[string]struct{})
	visitor(func(value string) {
		id := strings.TrimSpace(value)
		if id == "" {
			return
		}
		set[id] = struct{}{}
	})

	items := make([]string, 0, len(set))
	for id := range set {
		items = append(items, id)
	}
	sort.Strings(items)

	return items
}
