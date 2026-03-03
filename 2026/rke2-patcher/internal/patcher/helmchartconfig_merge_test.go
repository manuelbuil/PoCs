package patcher

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestFindConflictingHelmChartConfigs(t *testing.T) {
	tmpDir := t.TempDir()
	t.Setenv(manifestsDirEnv, tmpDir)
	t.Setenv(helmChartConfigFileEnv, "generated.yaml")
	t.Setenv(helmChartConfigNameEnv, "rke2-traefik")
	t.Setenv(helmNamespaceEnv, "kube-system")

	generatedPath, generatedContent := BuildHelmChartConfig("traefik", "rke2-traefik", "rancher/hardened-traefik", "v3.4.0")

	conflictOne := `apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-traefik
  namespace: kube-system
spec:
  valuesContent: |-
    service:
      type: LoadBalancer
`
	conflictTwo := `apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-traefik
  namespace: kube-system
spec:
  valuesSecrets:
    - name: custom-values
      keys:
        - values.yaml
`
	nonConflict := `apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-coredns
  namespace: kube-system
spec:
  valuesContent: |-
    image:
      tag: latest
`

	if err := os.WriteFile(filepath.Join(tmpDir, "a.yaml"), []byte(conflictOne), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(tmpDir, "b.yaml"), []byte(conflictTwo), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(tmpDir, "c.yaml"), []byte(nonConflict), 0644); err != nil {
		t.Fatal(err)
	}

	conflicts, err := FindConflictingHelmChartConfigs(generatedPath, generatedContent)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(conflicts) != 2 {
		t.Fatalf("expected 2 conflicts, got %d (%v)", len(conflicts), conflicts)
	}

	if !strings.HasSuffix(conflicts[0], "a.yaml") || !strings.HasSuffix(conflicts[1], "b.yaml") {
		t.Fatalf("unexpected conflicts order/content: %v", conflicts)
	}
}

func TestMergeHelmChartConfigWithFiles(t *testing.T) {
	tmpDir := t.TempDir()
	baseFile := filepath.Join(tmpDir, "existing.yaml")

	existingContent := `apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-traefik
  namespace: kube-system
spec:
  valuesContent: |-
    service:
      type: ClusterIP
    image:
      repository: old/repo
      tag: old-tag
  valuesSecrets:
    - name: existing-values
      keys:
        - values.yaml
`

	generatedContent := `apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-traefik
  namespace: kube-system
spec:
  valuesContent: |-
    image:
      repository: rancher/hardened-traefik
      tag: new-tag
`

	if err := os.WriteFile(baseFile, []byte(existingContent), 0644); err != nil {
		t.Fatal(err)
	}

	merged, err := MergeHelmChartConfigWithFiles(generatedContent, []string{baseFile})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !strings.Contains(merged, "type: ClusterIP") {
		t.Fatalf("expected merged content to keep existing non-conflicting valuesContent fields: %s", merged)
	}
	if !strings.Contains(merged, "repository: rancher/hardened-traefik") || !strings.Contains(merged, "tag: new-tag") {
		t.Fatalf("expected merged content to include generated image values: %s", merged)
	}
	if strings.Contains(merged, "old-tag") {
		t.Fatalf("expected generated values to override old tag: %s", merged)
	}
	if !strings.Contains(merged, "valuesSecrets") || !strings.Contains(merged, "existing-values") {
		t.Fatalf("expected merged content to preserve existing valuesSecrets: %s", merged)
	}
}

func TestMergeHelmChartConfigWithContents(t *testing.T) {
	existingContent := `apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-traefik
  namespace: kube-system
spec:
  valuesContent: |-
    service:
      type: ClusterIP
`

	generatedContent := `apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-traefik
  namespace: kube-system
spec:
  valuesContent: |-
    image:
      repository: rancher/hardened-traefik
      tag: new-tag
`

	merged, err := MergeHelmChartConfigWithContents(generatedContent, []string{existingContent})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !strings.Contains(merged, "type: ClusterIP") {
		t.Fatalf("expected merged content to include existing values content: %s", merged)
	}
	if !strings.Contains(merged, "repository: rancher/hardened-traefik") || !strings.Contains(merged, "tag: new-tag") {
		t.Fatalf("expected merged content to include generated image values: %s", merged)
	}
}

func TestHelmChartConfigIdentityFromContent(t *testing.T) {
	content := `apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-traefik
  namespace: kube-system
spec:
  valuesContent: |-
    image:
      repository: rancher/hardened-traefik
      tag: v3.4.0
`

	name, namespace, err := HelmChartConfigIdentityFromContent(content)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if name != "rke2-traefik" || namespace != "kube-system" {
		t.Fatalf("unexpected identity: %s/%s", namespace, name)
	}
}
