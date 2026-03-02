package kube

import (
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	semver "github.com/Masterminds/semver/v3"
	"github.com/manuelbuil/PoCs/2026/imagepatcher/internal/dockerhub"
)

const (
	kubeAPIURL              = "https://kubernetes.default.svc"
	serviceAccountTokenPath = "/var/run/secrets/kubernetes.io/serviceaccount/token"
	serviceAccountCAPath    = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
	traefikDaemonSetName    = "rke2-traefik"

	helmChartConfigEnabledEnv = "IMAGEPATCHER_WRITE_HELMCHARTCONFIG"
	manifestsDirEnv           = "IMAGEPATCHER_MANIFESTS_DIR"
	helmChartConfigFileEnv    = "IMAGEPATCHER_HELMCHARTCONFIG_FILE"
	helmChartConfigNameEnv    = "IMAGEPATCHER_HELMCHARTCONFIG_NAME"

	defaultManifestsDir        = "/var/lib/rancher/rke2/server/manifests"
	defaultHelmChartConfigFile = "rke2-traefik-config.yaml"
	defaultHelmChartConfigName = "rke2-traefik"
)

func isTruthy(value string) bool {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "1", "true", "yes", "on":
		return true
	default:
		return false
	}
}

func envOrDefault(key string, fallback string) string {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}

	return value
}

func renderTraefikHelmChartConfig(chartName string, imageName string, imageTag string) string {
	return fmt.Sprintf(`apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: %s
  namespace: kube-system
spec:
  valuesContent: |-
    image:
      repository: %s
      tag: %s
`, chartName, imageName, imageTag)
}

func WriteHelmChartConfigIfEnabled(imageName string, imageTag string) (bool, string, error) {
	if !isTruthy(os.Getenv(helmChartConfigEnabledEnv)) {
		return false, "", nil
	}

	manifestsDir := envOrDefault(manifestsDirEnv, defaultManifestsDir)
	fileName := envOrDefault(helmChartConfigFileEnv, defaultHelmChartConfigFile)
	chartName := envOrDefault(helmChartConfigNameEnv, defaultHelmChartConfigName)

	filePath := filepath.Join(manifestsDir, fileName)
	content := renderTraefikHelmChartConfig(chartName, imageName, imageTag)

	if err := os.WriteFile(filePath, []byte(content), 0644); err != nil {
		return false, filePath, err
	}

	return true, filePath, nil
}

func splitImageNameAndTag(image string) (string, string) {
	if strings.Contains(image, "@") {
		parts := strings.SplitN(image, "@", 2)
		return parts[0], parts[1]
	}

	lastSlash := strings.LastIndex(image, "/")
	lastColon := strings.LastIndex(image, ":")
	if lastColon > lastSlash {
		return image[:lastColon], image[lastColon+1:]
	}

	return image, "latest"
}

func GetTraefikImageFromKubeAPI() (string, string, error) {
	tokenBytes, err := os.ReadFile(serviceAccountTokenPath)
	if err != nil {
		return "", "", err
	}

	caBytes, err := os.ReadFile(serviceAccountCAPath)
	if err != nil {
		return "", "", err
	}

	certPool := x509.NewCertPool()
	if !certPool.AppendCertsFromPEM(caBytes) {
		return "", "", fmt.Errorf("failed to parse kubernetes CA certificate")
	}

	client := &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{RootCAs: certPool},
		},
	}

	daemonSetURL := kubeAPIURL + "/apis/apps/v1/namespaces/kube-system/daemonsets/" + traefikDaemonSetName
	req, err := http.NewRequest(http.MethodGet, daemonSetURL, nil)
	if err != nil {
		return "", "", err
	}
	req.Header.Set("Authorization", "Bearer "+strings.TrimSpace(string(tokenBytes)))

	resp, err := client.Do(req)
	if err != nil {
		return "", "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", "", fmt.Errorf("kube api returned status %d", resp.StatusCode)
	}

	var result struct {
		Spec struct {
			Template struct {
				Spec struct {
					Containers []struct {
						Name  string `json:"name"`
						Image string `json:"image"`
					} `json:"containers"`
				} `json:"spec"`
			} `json:"template"`
		} `json:"spec"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", "", err
	}

	if len(result.Spec.Template.Spec.Containers) == 0 {
		return "", "", fmt.Errorf("daemonset %q has no containers", traefikDaemonSetName)
	}

	image := result.Spec.Template.Spec.Containers[0].Image
	for _, container := range result.Spec.Template.Spec.Containers {
		if strings.EqualFold(container.Name, "traefik") {
			image = container.Image
			break
		}
	}

	imageName, imageTag := splitImageNameAndTag(image)
	return imageName, imageTag, nil
}

func normalizeTag(tag string) (string, error) {
	version, err := semver.NewVersion(tag)
	if err != nil {
		return "", err
	}

	return version.String(), nil
}

func GetTraefikTagsBehind() (int, string, []string, error) {
	_, currentTag, err := GetTraefikImageFromKubeAPI()
	if err != nil {
		return 0, "", nil, err
	}

	latestTags, err := dockerhub.GetLatestTags()
	if err != nil {
		return 0, currentTag, nil, err
	}

	normalizedCurrentTag, err := normalizeTag(currentTag)
	if err != nil {
		return 0, currentTag, latestTags, fmt.Errorf("current traefik tag is not valid semver: %w", err)
	}

	for index, tag := range latestTags {
		normalizedTag, err := normalizeTag(tag)
		if err != nil {
			continue
		}

		if normalizedTag == normalizedCurrentTag {
			return index, currentTag, latestTags, nil
		}
	}

	return -1, currentTag, latestTags, fmt.Errorf("current traefik tag %q is not within latest %d tags", currentTag, len(latestTags))
}
