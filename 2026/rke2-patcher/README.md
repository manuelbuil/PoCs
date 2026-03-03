# rke2-patcher

`rke2-patcher` is a small CLI to inspect and patch RKE2 component images.

## Build

```bash
go build -o rke2-patcher .
```

Or with Make:

```bash
make build
```

## Commands

```bash
rke2-patcher --version
rke2-patcher image-cve <component>
rke2-patcher image-list <component>
rke2-patcher image-patch <component>
rke2-patcher image-patch <component> --dry-run
```

Make targets:

```bash
make version
make image-cve COMPONENT=traefik
make image-list COMPONENT=traefik
make image-patch COMPONENT=traefik
```

### 1) CVEs of current running image

```bash
rke2-patcher image-cve traefik
```

- Looks up the current running image in the cluster for the selected component.
- Verifies the component workload exists in `kube-system` (DaemonSet/Deployment mapping).
- Scans it for CVEs using `trivy` (preferred) or `grype` (fallback).

### 2) List available images (tags)

```bash
rke2-patcher image-list traefik
```

- Lists recent tags from Docker Hub for the selected component repository.
- Highlights tags currently in use by running pods as `"<-- in use"` when cluster access is available.

### 3) Patch to latest image

```bash
rke2-patcher image-patch traefik
```

```bash
rke2-patcher image-patch traefik --dry-run
```

- Detects the current running image repository in-cluster.
- Verifies the component workload exists in `kube-system` (DaemonSet/Deployment mapping).
- Gets the latest tag from Docker Hub.
- Writes a `HelmChartConfig` manifest so RKE2 can use the latest tag.
- With `--dry-run`, prints the exact `HelmChartConfig` that would be written and does not write any file.
- Refuses to patch if the target tag is not newer than the currently running tag.
- If a `HelmChartConfig` object already exists in the cluster for the same chart name and namespace, asks for confirmation before attempting a merge.
- If merge is approved, prints the merged output in dry-run format and asks for a second confirmation before writing.
- For `canal`, it updates the chart values under `calico.cniImage`, `calico.nodeImage`, `calico.flexvolImage`, and `calico.kubeControllerImage`.
- For `calico-operator`, it updates `tigeraOperator.image`, `tigeraOperator.version`, and `tigeraOperator.registry`.
- For `cilium-operator`, it updates `operator.image.repository` and `operator.image.tag`.
- For `ingress-nginx`, it updates `controller.image.repository` and `controller.image.tag`.

## Supported components

- `traefik` -> `rancher/hardened-traefik`
- `ingress-nginx` -> `rancher/nginx-ingress-controller`
- `coredns` -> `rancher/hardened-coredns`
- `dns-node-cache` -> `rancher/hardened-dns-node-cache`
- `calico-operator` -> `rancher/mirrored-calico-operator`
- `cilium-operator` -> `rancher/mirrored-cilium-operator-generic`
- `metrics-server` -> `rancher/hardened-k8s-metrics-server`
- `flannel` -> `rancher/hardened-flannel`
- `canal` -> `rancher/hardened-calico`
- `csi-snapshotter` -> `rancher/hardened-csi-snapshotter`
- `cluster-autoscaler` -> `rancher/hardened-cluster-autoscaler`
- `snapshot-controller` -> `rancher/hardened-snapshot-controller`

## Requirements

- Kubernetes API access for `image-cve` and `image-patch`, using one of:
  - In-cluster service account files:
    - `/var/run/secrets/kubernetes.io/serviceaccount/token`
    - `/var/run/secrets/kubernetes.io/serviceaccount/ca.crt`
  - Kubeconfig (host binary mode on control-plane):
    - `RKE2_PATCHER_KUBECONFIG`, or
    - `KUBECONFIG` (first file in list), or
    - `/etc/rancher/rke2/rke2.yaml`, or
    - `~/.kube/config`
- Network access to Docker Hub.
- For `image-cve`, install at least one scanner:
  - `trivy`, or
  - `grype`

## Environment variables

The `image-patch` command supports these overrides:

- `RKE2_PATCHER_KUBECONFIG`
  - Optional kubeconfig path used when service account auth is not available.
  - Useful when running as a host binary on control-plane nodes.

- `RKE2_PATCHER_MANIFESTS_DIR`
  - Directory where the manifest file is written.
  - Default: `/var/lib/rancher/rke2/server/manifests`
- `RKE2_PATCHER_HELMCHARTCONFIG_FILE`
  - Output filename for the generated manifest.
  - Default: `<component>-config-rke2-patcher.yaml`
  - If the file already exists, `image-patch` overwrites it.
- `RKE2_PATCHER_HELMCHARTCONFIG_NAME`
  - `.metadata.name` for the generated `HelmChartConfig`.
  - Default: component-specific chart config name (for example `rke2-traefik`).
- `RKE2_PATCHER_HELM_NAMESPACE`
  - `.metadata.namespace` for the generated `HelmChartConfig`.
  - Default: `kube-system`

Example:

```bash
RKE2_PATCHER_MANIFESTS_DIR=/tmp \
RKE2_PATCHER_HELMCHARTCONFIG_FILE=traefik-config-rke2-patcher.yaml \
RKE2_PATCHER_HELMCHARTCONFIG_NAME=rke2-traefik \
RKE2_PATCHER_HELM_NAMESPACE=kube-system \
./rke2-patcher image-patch traefik
```
