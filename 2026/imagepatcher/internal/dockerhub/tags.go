package dockerhub

import (
	"encoding/json"
	"fmt"
	"net/http"

	semver "github.com/Masterminds/semver/v3"
)

const (
	tagsURL = "https://hub.docker.com/v2/repositories/rancher/hardened-traefik/tags?page_size=10&ordering=last_updated"
)

func isValidSemver(tag string) bool {
	_, err := semver.NewVersion(tag)
	return err == nil
}

func GetLatestTag() (string, error) {
	resp, err := http.Get(tagsURL)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	var result struct {
		Results []struct {
			Name string `json:"name"`
		} `json:"results"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", err
	}

	for _, tag := range result.Results {
		if tag.Name != "latest" && isValidSemver(tag.Name) {
			return tag.Name, nil
		}
	}

	return "", fmt.Errorf("no valid tags found")
}

func GetLatestTags() ([]string, error) {
	resp, err := http.Get(tagsURL)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result struct {
		Results []struct {
			Name string `json:"name"`
		} `json:"results"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}

	latestTags := make([]string, 0, 3)
	for _, tag := range result.Results {
		if tag.Name != "latest" && isValidSemver(tag.Name) {
			latestTags = append(latestTags, tag.Name)
			if len(latestTags) == 3 {
				return latestTags, nil
			}
		}
	}

	if len(latestTags) == 0 {
		return nil, fmt.Errorf("no valid tags found")
	}

	return nil, fmt.Errorf("only found %d valid tags", len(latestTags))
}
