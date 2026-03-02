package components

import (
	"fmt"
	"sort"
	"strings"
)

type Component struct {
	Name                string
	DockerHubRepository string
	HelmChartConfigName string
	Workloads           []WorkloadRef
}

type WorkloadRef struct {
	Kind      string
	Namespace string
	Name      string
}

var registry = map[string]Component{
	"traefik": {
		Name:                "rke2-traefik",
		DockerHubRepository: "rancher/hardened-traefik",
		HelmChartConfigName: "rke2-traefik",
		Workloads: []WorkloadRef{{
			Kind:      "daemonset",
			Namespace: "kube-system",
			Name:      "rke2-traefik",
		}},
	},
	"ingress-nginx": {
		Name:                "rke2-ingress-nginx-controller",
		DockerHubRepository: "rancher/nginx-ingress-controller",
		HelmChartConfigName: "rke2-ingress-nginx",
		Workloads: []WorkloadRef{{
			Kind:      "daemonset",
			Namespace: "kube-system",
			Name:      "rke2-ingress-nginx-controller",
		}},
	},
	"coredns": {
		Name:                "coredns",
		DockerHubRepository: "rancher/hardened-coredns",
		HelmChartConfigName: "rke2-coredns",
		Workloads: []WorkloadRef{
			{
				Kind:      "deployment",
				Namespace: "kube-system",
				Name:      "rke2-coredns-rke2-coredns",
			},
			{
				Kind:      "deployment",
				Namespace: "kube-system",
				Name:      "rke2-coredns-rke2-coredns-autoscaler",
			},
		},
	},
	"dns-node-cache": {
		Name:                "dns-node-cache",
		DockerHubRepository: "rancher/hardened-dns-node-cache",
		HelmChartConfigName: "rke2-coredns",
	},
	"calico-operator": {
		Name:                "calico-operator",
		DockerHubRepository: "rancher/mirrored-calico-operator",
		HelmChartConfigName: "rke2-calico",
		Workloads: []WorkloadRef{{
			Kind:      "deployment",
			Namespace: "tigera-operator",
			Name:      "tigera-operator",
		}},
	},
	"cilium-operator": {
		Name:                "cilium-operator",
		DockerHubRepository: "rancher/mirrored-cilium-operator-generic",
		HelmChartConfigName: "rke2-cilium",
		Workloads: []WorkloadRef{{
			Kind:      "deployment",
			Namespace: "kube-system",
			Name:      "cilium-operator",
		}},
	},
	"metrics-server": {
		Name:                "metrics-server",
		DockerHubRepository: "rancher/hardened-k8s-metrics-server",
		HelmChartConfigName: "rke2-metrics-server",
		Workloads: []WorkloadRef{{
			Kind:      "deployment",
			Namespace: "kube-system",
			Name:      "rke2-metrics-server",
		}},
	},
	"flannel": {
		Name:                "flannel",
		DockerHubRepository: "rancher/hardened-flannel",
		HelmChartConfigName: "rke2-flannel",
	},
	"canal": {
		Name:                "canal",
		DockerHubRepository: "rancher/hardened-calico",
		HelmChartConfigName: "rke2-canal",
		Workloads: []WorkloadRef{{
			Kind:      "daemonset",
			Namespace: "kube-system",
			Name:      "rke2-canal",
		}},
	},
	"csi-snapshotter": {
		Name:                "csi-snapshotter",
		DockerHubRepository: "rancher/hardened-csi-snapshotter",
		HelmChartConfigName: "rke2-snapshot-controller",
	},
	"cluster-autoscaler": {
		Name:                "cluster-autoscaler",
		DockerHubRepository: "rancher/hardened-cluster-autoscaler",
		HelmChartConfigName: "rke2-cluster-autoscaler",
	},
	"snapshot-controller": {
		Name:                "snapshot-controller",
		DockerHubRepository: "rancher/hardened-snapshot-controller",
		HelmChartConfigName: "rke2-snapshot-controller",
		Workloads: []WorkloadRef{{
			Kind:      "deployment",
			Namespace: "kube-system",
			Name:      "rke2-snapshot-controller",
		}},
	},
}

func Resolve(name string) (Component, error) {
	key := strings.ToLower(strings.TrimSpace(name))
	component, found := registry[key]
	if !found {
		return Component{}, fmt.Errorf("unsupported component %q", name)
	}

	return component, nil
}

func Supported() []string {
	items := make([]string, 0, len(registry))
	for name := range registry {
		items = append(items, name)
	}
	sort.Strings(items)

	return items
}
