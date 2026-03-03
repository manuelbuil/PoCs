package kube

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"

	"gopkg.in/yaml.v3"
)

type HelmChartConfigObject struct {
	Name      string
	Namespace string
	Content   string
}

type helmChartConfigList struct {
	Items []helmChartConfigItem `json:"items"`
}

type helmChartConfigItem struct {
	APIVersion string         `json:"apiVersion"`
	Kind       string         `json:"kind"`
	Metadata   helmObjectMeta `json:"metadata"`
	Spec       map[string]any `json:"spec"`
}

type helmObjectMeta struct {
	Name      string `json:"name"`
	Namespace string `json:"namespace"`
}

// ListHelmChartConfigsByIdentity lists HelmChartConfig objects in the cluster that match the given name and namespace.
func ListHelmChartConfigsByIdentity(name string, namespace string) ([]HelmChartConfigObject, error) {
	trimmedName := strings.TrimSpace(name)
	trimmedNamespace := strings.TrimSpace(namespace)
	if trimmedName == "" {
		return nil, fmt.Errorf("helmchartconfig name cannot be empty")
	}
	if trimmedNamespace == "" {
		return nil, fmt.Errorf("helmchartconfig namespace cannot be empty")
	}

	api, err := kubeAPIClient()
	if err != nil {
		return nil, err
	}

	requestURL := fmt.Sprintf(
		"%s/apis/helm.cattle.io/v1/namespaces/%s/helmchartconfigs",
		api.BaseURL,
		url.PathEscape(trimmedNamespace),
	)

	req, err := http.NewRequest(http.MethodGet, requestURL, nil)
	if err != nil {
		return nil, err
	}
	if strings.TrimSpace(api.AuthHeader) != "" {
		req.Header.Set("Authorization", api.AuthHeader)
	}

	resp, err := api.Client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return nil, nil
	}
	if resp.StatusCode != http.StatusOK {
		bodyBytes, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return nil, fmt.Errorf("kube api returned status %d when listing helmchartconfigs in %s: %s", resp.StatusCode, trimmedNamespace, strings.TrimSpace(string(bodyBytes)))
	}

	var list helmChartConfigList
	if err := json.NewDecoder(resp.Body).Decode(&list); err != nil {
		return nil, err
	}

	results := make([]HelmChartConfigObject, 0, len(list.Items))
	for _, item := range list.Items {
		if strings.TrimSpace(item.Metadata.Name) != trimmedName {
			continue
		}
		if strings.TrimSpace(item.Metadata.Namespace) != trimmedNamespace {
			continue
		}

		manifest := helmChartConfigItem{
			APIVersion: item.APIVersion,
			Kind:       item.Kind,
			Metadata: helmObjectMeta{
				Name:      item.Metadata.Name,
				Namespace: item.Metadata.Namespace,
			},
			Spec: item.Spec,
		}
		if strings.TrimSpace(manifest.APIVersion) == "" {
			manifest.APIVersion = "helm.cattle.io/v1"
		}
		if strings.TrimSpace(manifest.Kind) == "" {
			manifest.Kind = "HelmChartConfig"
		}

		contentBytes, err := yaml.Marshal(manifest)
		if err != nil {
			return nil, err
		}

		results = append(results, HelmChartConfigObject{
			Name:      item.Metadata.Name,
			Namespace: item.Metadata.Namespace,
			Content:   string(contentBytes),
		})
	}

	return results, nil
}
