package patcher

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"
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

	if err := WriteHelmChartConfigContent(filePath, content); err != nil {
		return filePath, err
	}

	return filePath, nil
}

func WriteHelmChartConfigContent(filePath string, content string) error {
	if err := os.WriteFile(filePath, []byte(content), 0644); err != nil {
		return err
	}

	return nil
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

func FindConflictingHelmChartConfigs(targetFilePath string, generatedContent string) ([]string, error) {
	generatedDoc, err := parseSingleHelmChartConfig(generatedContent)
	if err != nil {
		return nil, fmt.Errorf("failed to parse generated HelmChartConfig: %w", err)
	}

	targetName := strings.TrimSpace(generatedDoc.Metadata.Name)
	targetNamespace := strings.TrimSpace(generatedDoc.Metadata.Namespace)
	if targetName == "" || targetNamespace == "" {
		return nil, fmt.Errorf("generated HelmChartConfig is missing metadata.name or metadata.namespace")
	}

	absTarget, err := filepath.Abs(targetFilePath)
	if err != nil {
		return nil, err
	}

	manifestDir := filepath.Dir(absTarget)
	entries, err := os.ReadDir(manifestDir)
	if err != nil {
		return nil, fmt.Errorf("failed to read manifests directory %q: %w", manifestDir, err)
	}

	var conflicts []string
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}

		fileName := strings.ToLower(entry.Name())
		if !strings.HasSuffix(fileName, ".yaml") && !strings.HasSuffix(fileName, ".yml") {
			continue
		}

		candidatePath := filepath.Join(manifestDir, entry.Name())
		absCandidate, err := filepath.Abs(candidatePath)
		if err != nil {
			return nil, err
		}

		if absCandidate == absTarget {
			continue
		}

		matches, err := fileContainsHelmChartConfig(absCandidate, targetName, targetNamespace)
		if err != nil {
			return nil, err
		}
		if matches {
			conflicts = append(conflicts, absCandidate)
		}
	}

	sort.Strings(conflicts)
	return conflicts, nil
}

func MergeHelmChartConfigWithFiles(generatedContent string, existingFiles []string) (string, error) {
	existingContents := make([]string, 0, len(existingFiles))
	for _, filePath := range existingFiles {
		data, err := os.ReadFile(filePath)
		if err != nil {
			return "", fmt.Errorf("failed reading manifest %q: %w", filePath, err)
		}
		existingContents = append(existingContents, string(data))
	}

	return MergeHelmChartConfigWithContents(generatedContent, existingContents)
}

func MergeHelmChartConfigWithContents(generatedContent string, existingContents []string) (string, error) {
	generatedDoc, err := parseSingleHelmChartConfig(generatedContent)
	if err != nil {
		return "", fmt.Errorf("failed to parse generated HelmChartConfig: %w", err)
	}

	targetName := strings.TrimSpace(generatedDoc.Metadata.Name)
	targetNamespace := strings.TrimSpace(generatedDoc.Metadata.Namespace)
	if targetName == "" || targetNamespace == "" {
		return "", fmt.Errorf("generated HelmChartConfig is missing metadata.name or metadata.namespace")
	}

	mergedSpec := map[string]any{}
	for _, content := range existingContents {
		spec, found, err := findMatchingSpecInContent(content, targetName, targetNamespace)
		if err != nil {
			return "", err
		}
		if !found {
			continue
		}

		mergedSpec = deepMergeMaps(mergedSpec, spec)
	}

	generatedSpec := generatedDoc.Spec
	if generatedSpec == nil {
		generatedSpec = map[string]any{}
	}

	existingValues, hasExistingValues := stringField(mergedSpec, "valuesContent")
	newValues, hasNewValues := stringField(generatedSpec, "valuesContent")
	if hasExistingValues && hasNewValues {
		combinedValues, err := mergeValuesContent(existingValues, newValues)
		if err != nil {
			return "", err
		}
		generatedSpec["valuesContent"] = combinedValues
	}

	mergedSpec = deepMergeMaps(mergedSpec, generatedSpec)

	mergedDoc := helmChartConfigDoc{
		APIVersion: generatedDoc.APIVersion,
		Kind:       generatedDoc.Kind,
		Metadata: metadataRef{
			Name:      generatedDoc.Metadata.Name,
			Namespace: generatedDoc.Metadata.Namespace,
		},
		Spec: mergedSpec,
	}

	if strings.TrimSpace(mergedDoc.APIVersion) == "" {
		mergedDoc.APIVersion = "helm.cattle.io/v1"
	}
	if strings.TrimSpace(mergedDoc.Kind) == "" {
		mergedDoc.Kind = "HelmChartConfig"
	}

	b, err := yaml.Marshal(mergedDoc)
	if err != nil {
		return "", err
	}

	if len(b) == 0 || b[len(b)-1] != '\n' {
		b = append(b, '\n')
	}

	return string(b), nil
}

func HelmChartConfigIdentityFromContent(content string) (string, string, error) {
	doc, err := parseSingleHelmChartConfig(content)
	if err != nil {
		return "", "", err
	}

	name := strings.TrimSpace(doc.Metadata.Name)
	namespace := strings.TrimSpace(doc.Metadata.Namespace)
	if name == "" || namespace == "" {
		return "", "", fmt.Errorf("HelmChartConfig content missing metadata.name or metadata.namespace")
	}

	return name, namespace, nil
}

type helmChartConfigDoc struct {
	APIVersion string         `yaml:"apiVersion"`
	Kind       string         `yaml:"kind"`
	Metadata   metadataRef    `yaml:"metadata"`
	Spec       map[string]any `yaml:"spec,omitempty"`
}

type metadataRef struct {
	Name      string `yaml:"name"`
	Namespace string `yaml:"namespace"`
}

func parseSingleHelmChartConfig(content string) (helmChartConfigDoc, error) {
	decoder := yaml.NewDecoder(strings.NewReader(content))
	for {
		var doc helmChartConfigDoc
		err := decoder.Decode(&doc)
		if err == io.EOF {
			break
		}
		if err != nil {
			return helmChartConfigDoc{}, err
		}

		if strings.EqualFold(strings.TrimSpace(doc.Kind), "HelmChartConfig") {
			return doc, nil
		}
	}

	return helmChartConfigDoc{}, fmt.Errorf("no HelmChartConfig document found")
}

func fileContainsHelmChartConfig(filePath string, targetName string, targetNamespace string) (bool, error) {
	_, found, err := findMatchingSpec(filePath, targetName, targetNamespace)
	if err != nil {
		return false, err
	}

	return found, nil
}

func findMatchingSpec(filePath string, targetName string, targetNamespace string) (map[string]any, bool, error) {
	data, err := os.ReadFile(filePath)
	if err != nil {
		return nil, false, fmt.Errorf("failed reading manifest %q: %w", filePath, err)
	}

	return findMatchingSpecInContent(string(data), targetName, targetNamespace)
}

func findMatchingSpecInContent(content string, targetName string, targetNamespace string) (map[string]any, bool, error) {
	decoder := yaml.NewDecoder(strings.NewReader(content))

	for {
		var doc helmChartConfigDoc
		err := decoder.Decode(&doc)
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, false, fmt.Errorf("failed parsing HelmChartConfig content: %w", err)
		}

		if !strings.EqualFold(strings.TrimSpace(doc.Kind), "HelmChartConfig") {
			continue
		}

		if strings.TrimSpace(doc.Metadata.Name) == targetName && strings.TrimSpace(doc.Metadata.Namespace) == targetNamespace {
			if doc.Spec == nil {
				return map[string]any{}, true, nil
			}
			return deepCopyMap(doc.Spec), true, nil
		}
	}

	return nil, false, nil
}

func deepMergeMaps(base map[string]any, overlay map[string]any) map[string]any {
	result := deepCopyMap(base)
	if result == nil {
		result = map[string]any{}
	}

	for key, overlayValue := range overlay {
		baseValue, found := result[key]
		if found {
			baseMap, baseIsMap := baseValue.(map[string]any)
			overlayMap, overlayIsMap := overlayValue.(map[string]any)
			if baseIsMap && overlayIsMap {
				result[key] = deepMergeMaps(baseMap, overlayMap)
				continue
			}
		}

		result[key] = deepCopyValue(overlayValue)
	}

	return result
}

func deepCopyMap(input map[string]any) map[string]any {
	if input == nil {
		return nil
	}

	result := make(map[string]any, len(input))
	for key, value := range input {
		result[key] = deepCopyValue(value)
	}

	return result
}

func deepCopyValue(value any) any {
	switch typed := value.(type) {
	case map[string]any:
		return deepCopyMap(typed)
	case []any:
		copied := make([]any, len(typed))
		for i := range typed {
			copied[i] = deepCopyValue(typed[i])
		}
		return copied
	default:
		return typed
	}
}

func stringField(spec map[string]any, field string) (string, bool) {
	if spec == nil {
		return "", false
	}

	raw, found := spec[field]
	if !found {
		return "", false
	}

	value, ok := raw.(string)
	if !ok {
		return "", false
	}

	return value, true
}

func mergeValuesContent(existing string, incoming string) (string, error) {
	existingTrimmed := strings.TrimSpace(existing)
	incomingTrimmed := strings.TrimSpace(incoming)

	if existingTrimmed == "" {
		return incoming, nil
	}
	if incomingTrimmed == "" {
		return existing, nil
	}

	var existingValues any
	if err := yaml.Unmarshal([]byte(existing), &existingValues); err != nil {
		return "", fmt.Errorf("failed to parse existing valuesContent: %w", err)
	}

	var incomingValues any
	if err := yaml.Unmarshal([]byte(incoming), &incomingValues); err != nil {
		return "", fmt.Errorf("failed to parse generated valuesContent: %w", err)
	}

	mergedValues := deepMergeValue(existingValues, incomingValues)
	b, err := yaml.Marshal(mergedValues)
	if err != nil {
		return "", err
	}

	return strings.TrimRight(string(b), "\n"), nil
}

func deepMergeValue(base any, overlay any) any {
	baseMap, baseIsMap := base.(map[string]any)
	overlayMap, overlayIsMap := overlay.(map[string]any)
	if baseIsMap && overlayIsMap {
		return deepMergeMaps(baseMap, overlayMap)
	}

	return deepCopyValue(overlay)
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
