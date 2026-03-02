package dockerhub

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const baseURL = "https://hub.docker.com/v2/namespaces"

type Tag struct {
	Name        string
	LastUpdated time.Time
}

type tagsPage struct {
	Next    string `json:"next"`
	Results []struct {
		Name        string `json:"name"`
		LastUpdated string `json:"last_updated"`
	} `json:"results"`
}

func ListTags(repository string, limit int) ([]Tag, error) {
	if limit <= 0 {
		return nil, fmt.Errorf("limit must be greater than zero")
	}

	namespace, repo, err := splitRepository(repository)
	if err != nil {
		return nil, err
	}

	next := fmt.Sprintf("%s/%s/repositories/%s/tags?page_size=100&ordering=last_updated", baseURL, url.PathEscape(namespace), url.PathEscape(repo))
	tags := make([]Tag, 0, limit)

	for next != "" && len(tags) < limit {
		page, pageErr := getTagsPage(next)
		if pageErr != nil {
			return nil, pageErr
		}

		for _, result := range page.Results {
			if strings.EqualFold(result.Name, "latest") {
				continue
			}

			tag := Tag{Name: result.Name}
			if result.LastUpdated != "" {
				parsed, parseErr := time.Parse(time.RFC3339Nano, result.LastUpdated)
				if parseErr == nil {
					tag.LastUpdated = parsed
				}
			}

			tags = append(tags, tag)
			if len(tags) == limit {
				break
			}
		}

		next = page.Next
	}

	if len(tags) == 0 {
		return nil, fmt.Errorf("no tags found for repository %q", repository)
	}

	return tags, nil
}

func LatestTag(repository string) (Tag, error) {
	tags, err := ListTags(repository, 1)
	if err != nil {
		return Tag{}, err
	}

	return tags[0], nil
}

func getTagsPage(requestURL string) (tagsPage, error) {
	resp, err := http.Get(requestURL)
	if err != nil {
		return tagsPage{}, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		bodyBytes, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return tagsPage{}, fmt.Errorf("docker hub API returned status %d: %s", resp.StatusCode, strings.TrimSpace(string(bodyBytes)))
	}

	var page tagsPage
	if err := json.NewDecoder(resp.Body).Decode(&page); err != nil {
		return tagsPage{}, err
	}

	return page, nil
}

func splitRepository(repository string) (string, string, error) {
	trimmed := strings.TrimSpace(repository)
	parts := strings.Split(trimmed, "/")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return "", "", fmt.Errorf("repository %q must be in the format <namespace>/<repo>", repository)
	}

	return parts[0], parts[1], nil
}
