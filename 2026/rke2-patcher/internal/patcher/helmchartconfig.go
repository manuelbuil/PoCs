package patcher

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const (
	manifestsDirEnv = "RKE2_PATCHER_MANIFESTS_DIR"

	helmChartConfigFileEnv = "RKE2_PATCHER_HELMCHARTCONFIG_FILE"
	helmChartConfigNameEnv = "RKE2_PATCHER_HELMCHARTCONFIG_NAME"
	helmNamespaceEnv       = "RKE2_PATCHER_HELM_NAMESPACE"

	defaultManifestsDir = "/var/lib/rancher/rke2/server/manifests"
	defaultNamespace    = "kube-system"
)

func WriteHelmChartConfig(componentName string, defaultChartConfigName string, imageName string, imageTag string) (string, error) {
	filePath, content := BuildHelmChartConfig(componentName, defaultChartConfigName, imageName, imageTag)

	if err := os.WriteFile(filePath, []byte(content), 0644); err != nil {
		return filePath, err
	}

	return filePath, nil
}

func BuildHelmChartConfig(componentName string, defaultChartConfigName string, imageName string, imageTag string) (string, string) {
	manifestsDir := envOrDefault(manifestsDirEnv, defaultManifestsDir)
	helmChartConfigFile := envOrDefault(helmChartConfigFileEnv, componentName+"-config-rke2-patcher.yaml")
	helmChartConfigName := envOrDefault(helmChartConfigNameEnv, defaultChartConfigName)
	namespace := envOrDefault(helmNamespaceEnv, defaultNamespace)

	filePath := filepath.Join(manifestsDir, helmChartConfigFile)
	content := renderHelmChartConfig(componentName, helmChartConfigName, namespace, imageName, imageTag)

	return filePath, content
}

func renderHelmChartConfig(componentName string, chartName string, namespace string, imageName string, imageTag string) string {
	valuesContent := renderValuesContent(componentName, chartName, imageName, imageTag)

	return fmt.Sprintf(`apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: %s
  namespace: %s
spec:
  valuesContent: |-
%s
`, chartName, namespace, valuesContent)
}

func renderValuesContent(componentName string, chartName string, imageName string, imageTag string) string {
	if strings.EqualFold(strings.TrimSpace(componentName), "calico-operator") || strings.EqualFold(strings.TrimSpace(chartName), "rke2-calico") {
		image := strings.TrimPrefix(strings.TrimSpace(imageName), "docker.io/")
		if image == "" {
			image = imageName
		}

		return fmt.Sprintf(`    tigeraOperator:
      image: %s
      version: %s
      registry: docker.io`, image, imageTag)
	}

	if strings.EqualFold(strings.TrimSpace(componentName), "ingress-nginx") || strings.EqualFold(strings.TrimSpace(chartName), "rke2-ingress-nginx") {
		return fmt.Sprintf(`    controller:
      image:
        repository: %s
        tag: %s`, imageName, imageTag)
	}

	if strings.EqualFold(strings.TrimSpace(componentName), "cilium-operator") || strings.EqualFold(strings.TrimSpace(chartName), "rke2-cilium") {
		repository := strings.TrimSuffix(strings.TrimSpace(imageName), "-generic")
		if repository == "" {
			repository = imageName
		}

		return fmt.Sprintf(`    operator:
      image:
        repository: %s
        tag: %s`, repository, imageTag)
	}

	if strings.EqualFold(strings.TrimSpace(componentName), "canal") || strings.EqualFold(strings.TrimSpace(chartName), "rke2-canal") {
		return fmt.Sprintf(`    calico:
      cniImage:
        repository: %s
        tag: %s
      nodeImage:
        repository: %s
        tag: %s
      flexvolImage:
        repository: %s
        tag: %s
      kubeControllerImage:
        repository: %s
        tag: %s`, imageName, imageTag, imageName, imageTag, imageName, imageTag, imageName, imageTag)
	}

	return fmt.Sprintf(`    image:
      repository: %s
      tag: %s`, imageName, imageTag)
}

func envOrDefault(key string, fallback string) string {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}

	return value
}
