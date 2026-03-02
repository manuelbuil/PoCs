package kube

import (
	"crypto/tls"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/manuelbuil/PoCs/2026/rke2-patcher/internal/components"
	"gopkg.in/yaml.v3"
)

const (
	kubeAPIURL              = "https://kubernetes.default.svc"
	serviceAccountTokenPath = "/var/run/secrets/kubernetes.io/serviceaccount/token"
	serviceAccountCAPath    = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"

	kubeconfigPathEnv = "RKE2_PATCHER_KUBECONFIG"
)

type kubeAPI struct {
	Client     *http.Client
	BaseURL    string
	AuthHeader string
}

type PodImageSummary struct {
	Image string
	Count int
}

type podList struct {
	Continue string `json:"continue"`
	Items    []struct {
		Status struct {
			Phase string `json:"phase"`
		} `json:"status"`
		Spec struct {
			InitContainers []struct {
				Image string `json:"image"`
			} `json:"initContainers"`
			Containers []struct {
				Image string `json:"image"`
			} `json:"containers"`
		} `json:"spec"`
	} `json:"items"`
}

func ListRunningImagesByRepository(componentRepository string) ([]PodImageSummary, error) {
	trimmedRepo := strings.TrimSpace(componentRepository)
	if trimmedRepo == "" {
		return nil, fmt.Errorf("component repository cannot be empty")
	}

	api, err := kubeAPIClient()
	if err != nil {
		return nil, err
	}

	counts := make(map[string]int)
	continueToken := ""
	for {
		list, listErr := listPodsPage(api, continueToken)
		if listErr != nil {
			return nil, listErr
		}

		for _, item := range list.Items {
			if item.Status.Phase != "Running" {
				continue
			}

			for _, container := range item.Spec.InitContainers {
				if imageBelongsToRepository(container.Image, trimmedRepo) {
					counts[container.Image]++
				}
			}

			for _, container := range item.Spec.Containers {
				if imageBelongsToRepository(container.Image, trimmedRepo) {
					counts[container.Image]++
				}
			}
		}

		if strings.TrimSpace(list.Continue) == "" {
			break
		}
		continueToken = list.Continue
	}

	if len(counts) == 0 {
		return nil, fmt.Errorf("no running image found in cluster for repository %q", componentRepository)
	}

	images := make([]PodImageSummary, 0, len(counts))
	for image, count := range counts {
		images = append(images, PodImageSummary{Image: image, Count: count})
	}

	sort.Slice(images, func(i int, j int) bool {
		if images[i].Count == images[j].Count {
			return images[i].Image < images[j].Image
		}

		return images[i].Count > images[j].Count
	})

	return images, nil
}

func EnsureAnyWorkloadExists(workloads []components.WorkloadRef) error {
	if len(workloads) == 0 {
		return nil
	}

	api, err := kubeAPIClient()
	if err != nil {
		return err
	}

	var checked []string
	for _, workload := range workloads {
		namespace := strings.TrimSpace(workload.Namespace)
		if namespace == "" {
			namespace = "kube-system"
		}

		kind := strings.ToLower(strings.TrimSpace(workload.Kind))
		name := strings.TrimSpace(workload.Name)
		if kind == "" || name == "" {
			continue
		}

		exists, checkErr := workloadExists(api, kind, namespace, name)
		checked = append(checked, fmt.Sprintf("%s/%s/%s", kind, namespace, name))
		if checkErr != nil {
			return checkErr
		}

		if exists {
			return nil
		}
	}

	if len(checked) == 0 {
		return fmt.Errorf("no valid workload references configured")
	}

	return fmt.Errorf("component workload not found in cluster (checked: %s)", strings.Join(checked, ", "))
}

func kubeAPIClient() (kubeAPI, error) {
	if _, tokenErr := os.Stat(serviceAccountTokenPath); tokenErr == nil {
		if _, caErr := os.Stat(serviceAccountCAPath); caErr == nil {
			api, err := inClusterClient()
			if err == nil {
				return api, nil
			}
		}
	}

	return kubeconfigClient()
}

func inClusterClient() (kubeAPI, error) {
	tokenBytes, err := os.ReadFile(serviceAccountTokenPath)
	if err != nil {
		return kubeAPI{}, err
	}

	caBytes, err := os.ReadFile(serviceAccountCAPath)
	if err != nil {
		return kubeAPI{}, err
	}

	certPool := x509.NewCertPool()
	if !certPool.AppendCertsFromPEM(caBytes) {
		return kubeAPI{}, fmt.Errorf("failed to parse kubernetes CA certificate")
	}

	client := &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{RootCAs: certPool},
		},
	}

	return kubeAPI{
		Client:     client,
		BaseURL:    kubeAPIURL,
		AuthHeader: "Bearer " + strings.TrimSpace(string(tokenBytes)),
	}, nil
}

func kubeconfigClient() (kubeAPI, error) {
	path, err := discoverKubeconfigPath()
	if err != nil {
		return kubeAPI{}, err
	}

	configBytes, err := os.ReadFile(path)
	if err != nil {
		return kubeAPI{}, fmt.Errorf("failed to read kubeconfig %q: %w", path, err)
	}

	var config kubeconfig
	if err := yaml.Unmarshal(configBytes, &config); err != nil {
		return kubeAPI{}, fmt.Errorf("failed to parse kubeconfig %q: %w", path, err)
	}

	clusterName, userName, err := config.resolveContext()
	if err != nil {
		return kubeAPI{}, err
	}

	cluster, err := config.findCluster(clusterName)
	if err != nil {
		return kubeAPI{}, err
	}

	user, err := config.findUser(userName)
	if err != nil {
		return kubeAPI{}, err
	}

	tlsConfig, err := buildTLSConfig(cluster, user, filepath.Dir(path))
	if err != nil {
		return kubeAPI{}, err
	}

	authHeader, err := buildAuthHeader(user, filepath.Dir(path))
	if err != nil {
		return kubeAPI{}, err
	}

	baseURL := strings.TrimSpace(cluster.Server)
	if baseURL == "" {
		return kubeAPI{}, fmt.Errorf("kubeconfig cluster server is empty")
	}

	client := &http.Client{Transport: &http.Transport{TLSClientConfig: tlsConfig}}

	return kubeAPI{Client: client, BaseURL: strings.TrimRight(baseURL, "/"), AuthHeader: authHeader}, nil
}

func listPodsPage(api kubeAPI, continueToken string) (podList, error) {
	requestURL := api.BaseURL + "/api/v1/pods?limit=500"
	if strings.TrimSpace(continueToken) != "" {
		requestURL += "&continue=" + url.QueryEscape(continueToken)
	}

	req, err := http.NewRequest(http.MethodGet, requestURL, nil)
	if err != nil {
		return podList{}, err
	}
	if strings.TrimSpace(api.AuthHeader) != "" {
		req.Header.Set("Authorization", api.AuthHeader)
	}

	resp, err := api.Client.Do(req)
	if err != nil {
		return podList{}, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		bodyBytes, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return podList{}, fmt.Errorf("kube api returned status %d: %s", resp.StatusCode, strings.TrimSpace(string(bodyBytes)))
	}

	var list podList
	if err := json.NewDecoder(resp.Body).Decode(&list); err != nil {
		return podList{}, err
	}

	return list, nil
}

func workloadExists(api kubeAPI, kind string, namespace string, name string) (bool, error) {
	resource := ""
	switch kind {
	case "daemonset":
		resource = "daemonsets"
	case "deployment":
		resource = "deployments"
	default:
		return false, fmt.Errorf("unsupported workload kind %q", kind)
	}

	requestURL := fmt.Sprintf(
		"%s/apis/apps/v1/namespaces/%s/%s/%s",
		api.BaseURL,
		url.PathEscape(namespace),
		resource,
		url.PathEscape(name),
	)

	req, err := http.NewRequest(http.MethodGet, requestURL, nil)
	if err != nil {
		return false, err
	}
	if strings.TrimSpace(api.AuthHeader) != "" {
		req.Header.Set("Authorization", api.AuthHeader)
	}

	resp, err := api.Client.Do(req)
	if err != nil {
		return false, err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return false, nil
	}
	if resp.StatusCode != http.StatusOK {
		bodyBytes, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return false, fmt.Errorf("kube api returned status %d when checking %s/%s/%s: %s", resp.StatusCode, kind, namespace, name, strings.TrimSpace(string(bodyBytes)))
	}

	return true, nil
}

type kubeconfig struct {
	CurrentContext string `yaml:"current-context"`
	Clusters       []struct {
		Name    string `yaml:"name"`
		Cluster struct {
			Server                   string `yaml:"server"`
			CertificateAuthority     string `yaml:"certificate-authority"`
			CertificateAuthorityData string `yaml:"certificate-authority-data"`
			InsecureSkipTLSVerify    bool   `yaml:"insecure-skip-tls-verify"`
		} `yaml:"cluster"`
	} `yaml:"clusters"`
	Contexts []struct {
		Name    string `yaml:"name"`
		Context struct {
			Cluster string `yaml:"cluster"`
			User    string `yaml:"user"`
		} `yaml:"context"`
	} `yaml:"contexts"`
	Users []struct {
		Name string `yaml:"name"`
		User struct {
			Token                 string `yaml:"token"`
			TokenFile             string `yaml:"tokenFile"`
			ClientCertificate     string `yaml:"client-certificate"`
			ClientCertificateData string `yaml:"client-certificate-data"`
			ClientKey             string `yaml:"client-key"`
			ClientKeyData         string `yaml:"client-key-data"`
		} `yaml:"user"`
	} `yaml:"users"`
}

type kubeconfigCluster struct {
	Server                   string
	CertificateAuthority     string
	CertificateAuthorityData string
	InsecureSkipTLSVerify    bool
}

type kubeconfigUser struct {
	Token                 string
	TokenFile             string
	ClientCertificate     string
	ClientCertificateData string
	ClientKey             string
	ClientKeyData         string
}

func (k kubeconfig) resolveContext() (string, string, error) {
	selected := strings.TrimSpace(k.CurrentContext)
	if selected == "" && len(k.Contexts) > 0 {
		selected = strings.TrimSpace(k.Contexts[0].Name)
	}
	if selected == "" {
		return "", "", fmt.Errorf("kubeconfig has no context")
	}

	for _, context := range k.Contexts {
		if strings.TrimSpace(context.Name) == selected {
			cluster := strings.TrimSpace(context.Context.Cluster)
			user := strings.TrimSpace(context.Context.User)
			if cluster == "" {
				return "", "", fmt.Errorf("kubeconfig context %q has no cluster", selected)
			}
			return cluster, user, nil
		}
	}

	return "", "", fmt.Errorf("kubeconfig context %q not found", selected)
}

func (k kubeconfig) findCluster(name string) (kubeconfigCluster, error) {
	for _, cluster := range k.Clusters {
		if strings.TrimSpace(cluster.Name) == name {
			return kubeconfigCluster{
				Server:                   cluster.Cluster.Server,
				CertificateAuthority:     cluster.Cluster.CertificateAuthority,
				CertificateAuthorityData: cluster.Cluster.CertificateAuthorityData,
				InsecureSkipTLSVerify:    cluster.Cluster.InsecureSkipTLSVerify,
			}, nil
		}
	}

	return kubeconfigCluster{}, fmt.Errorf("kubeconfig cluster %q not found", name)
}

func (k kubeconfig) findUser(name string) (kubeconfigUser, error) {
	if name == "" {
		return kubeconfigUser{}, nil
	}

	for _, user := range k.Users {
		if strings.TrimSpace(user.Name) == name {
			return kubeconfigUser{
				Token:                 user.User.Token,
				TokenFile:             user.User.TokenFile,
				ClientCertificate:     user.User.ClientCertificate,
				ClientCertificateData: user.User.ClientCertificateData,
				ClientKey:             user.User.ClientKey,
				ClientKeyData:         user.User.ClientKeyData,
			}, nil
		}
	}

	return kubeconfigUser{}, fmt.Errorf("kubeconfig user %q not found", name)
}

func discoverKubeconfigPath() (string, error) {
	candidates := make([]string, 0, 4)
	if configured := strings.TrimSpace(os.Getenv(kubeconfigPathEnv)); configured != "" {
		candidates = append(candidates, configured)
	}

	if configured := strings.TrimSpace(os.Getenv("KUBECONFIG")); configured != "" {
		parts := strings.Split(configured, ":")
		if len(parts) > 0 && strings.TrimSpace(parts[0]) != "" {
			candidates = append(candidates, strings.TrimSpace(parts[0]))
		}
	}

	candidates = append(candidates, "/etc/rancher/rke2/rke2.yaml")

	if homeDir, err := os.UserHomeDir(); err == nil && strings.TrimSpace(homeDir) != "" {
		candidates = append(candidates, filepath.Join(homeDir, ".kube", "config"))
	}

	for _, candidate := range candidates {
		if _, err := os.Stat(candidate); err == nil {
			return candidate, nil
		}
	}

	return "", fmt.Errorf("no kube auth available: service account not found and kubeconfig not found (checked %s)", strings.Join(candidates, ", "))
}

func buildTLSConfig(cluster kubeconfigCluster, user kubeconfigUser, kubeconfigDir string) (*tls.Config, error) {
	tlsConfig := &tls.Config{InsecureSkipVerify: cluster.InsecureSkipTLSVerify}

	if !cluster.InsecureSkipTLSVerify {
		caBytes, err := resolveBytes(cluster.CertificateAuthorityData, cluster.CertificateAuthority, kubeconfigDir)
		if err != nil {
			return nil, fmt.Errorf("failed to load kubeconfig CA: %w", err)
		}
		if len(caBytes) > 0 {
			certPool := x509.NewCertPool()
			if !certPool.AppendCertsFromPEM(caBytes) {
				return nil, fmt.Errorf("failed to parse kubeconfig CA certificate")
			}
			tlsConfig.RootCAs = certPool
		}
	}

	certBytes, certErr := resolveBytes(user.ClientCertificateData, user.ClientCertificate, kubeconfigDir)
	keyBytes, keyErr := resolveBytes(user.ClientKeyData, user.ClientKey, kubeconfigDir)
	if certErr != nil {
		return nil, fmt.Errorf("failed to load kubeconfig client certificate: %w", certErr)
	}
	if keyErr != nil {
		return nil, fmt.Errorf("failed to load kubeconfig client key: %w", keyErr)
	}
	if len(certBytes) > 0 || len(keyBytes) > 0 {
		if len(certBytes) == 0 || len(keyBytes) == 0 {
			return nil, fmt.Errorf("both client certificate and client key must be set in kubeconfig")
		}
		cert, err := tls.X509KeyPair(certBytes, keyBytes)
		if err != nil {
			return nil, fmt.Errorf("failed to parse kubeconfig client cert/key: %w", err)
		}
		tlsConfig.Certificates = []tls.Certificate{cert}
	}

	return tlsConfig, nil
}

func buildAuthHeader(user kubeconfigUser, kubeconfigDir string) (string, error) {
	token := strings.TrimSpace(user.Token)
	if token == "" && strings.TrimSpace(user.TokenFile) != "" {
		tokenFile := user.TokenFile
		if !filepath.IsAbs(tokenFile) {
			tokenFile = filepath.Join(kubeconfigDir, tokenFile)
		}
		tokenBytes, err := os.ReadFile(tokenFile)
		if err != nil {
			return "", fmt.Errorf("failed to read kubeconfig token file %q: %w", tokenFile, err)
		}
		token = strings.TrimSpace(string(tokenBytes))
	}

	if token == "" {
		return "", nil
	}

	return "Bearer " + token, nil
}

func resolveBytes(embeddedData string, filePath string, baseDir string) ([]byte, error) {
	trimmedData := strings.TrimSpace(embeddedData)
	if trimmedData != "" {
		decoded, err := base64.StdEncoding.DecodeString(trimmedData)
		if err != nil {
			return nil, err
		}
		return decoded, nil
	}

	trimmedPath := strings.TrimSpace(filePath)
	if trimmedPath == "" {
		return nil, nil
	}

	if !filepath.IsAbs(trimmedPath) {
		trimmedPath = filepath.Join(baseDir, trimmedPath)
	}

	bytes, err := os.ReadFile(trimmedPath)
	if err != nil {
		return nil, err
	}

	return bytes, nil
}

func imageBelongsToRepository(image string, componentRepository string) bool {
	imageRepository := imageNameWithoutTagOrDigest(image)
	if imageRepository == componentRepository {
		return true
	}

	return strings.HasSuffix(imageRepository, "/"+componentRepository)
}

func imageNameWithoutTagOrDigest(image string) string {
	trimmed := strings.TrimSpace(image)
	if idx := strings.Index(trimmed, "@"); idx >= 0 {
		trimmed = trimmed[:idx]
	}

	lastSlash := strings.LastIndex(trimmed, "/")
	lastColon := strings.LastIndex(trimmed, ":")
	if lastColon > lastSlash {
		trimmed = trimmed[:lastColon]
	}

	return trimmed
}

func SplitImage(image string) (string, string) {
	trimmed := strings.TrimSpace(image)
	if idx := strings.Index(trimmed, "@"); idx >= 0 {
		return trimmed[:idx], trimmed[idx+1:]
	}

	lastSlash := strings.LastIndex(trimmed, "/")
	lastColon := strings.LastIndex(trimmed, ":")
	if lastColon > lastSlash {
		return trimmed[:lastColon], trimmed[lastColon+1:]
	}

	return trimmed, "latest"
}
