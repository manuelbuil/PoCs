---
name: update-rke2-upgrade-responder-config
description: Updates the RKE2 release and CVE tracking configuration file in the rancher/upgrade-responders repository. Use this when asked to sync, update, or patch RKE2 release info.
license: Apache-2.0
metadata:
  version: "1.0.0"
  capabilities:
    - internet-access # Required to fetch RKE2 releases & VEX files
    - local-execution # Required to run trivy scans and git operations
---

# Skill: Update RKE2 Upgrade Responder Response Config

This skill automates the process of updating RKE2 releases and their associated CVEs in the `rancher/upgrade-responders` repository.

## Prerequisites
The agent executing this skill must have the following tools installed in its runtime environment:
- `git`
- `trivy` (v0.40.0 or later recommended)
- `curl` or `wget`
- `jq` (used to inspect the staging verification response)

## Target File & Format
- **Repository:** `https://github.com/rancher/upgrade-responders` (Target Branch: `staging`)
- **File Path:** `configs/rke2-security/upgrade-responder-response-config.yaml`
- **Format Note:** While the file extension is `.yaml`, it contains/expects array entries. Ensure your edits match the existing file's exact formatting structure (YAML or JSON-in-YAML flow style).

### Schema Template
Each version entry must follow this exact schema structure:
```json
{
  "name": "v1.35.2+rke2r1",
  "releaseDate": "2026-03-05T22:19:47Z",
  "tags": ["latest"],
  "extraInfo": {
    "cves": "CVE-2026-0001,CVE-2026-0002,CVE-2026-0003",
    "releaseNotesURL": "[https://github.com/rancher/rke2/releases/tag/v1.35.2%2Brke2r1](https://github.com/rancher/rke2/releases/tag/v1.35.2%2Brke2r1)"
  }
}
```

### Rules & Constraints

* Skip High Patch Versions: Ignore releases with a patch version greater than 14 (e.g., ignore v1.33.14+rke2r1).
* Skip EOL Minors: Ignore releases with a minor version of 32 or lower (e.g., ignore v1.31.6+rke2r1).
* CVE Limit: Once a release entry contains 5 CRITICAL CVEs, do not scan it or update its CVE list further.
* Re-scan Existing Releases (IMPORTANT): CVE scanning is NOT limited to new/missing releases. On EVERY run you MUST re-scan every non-EOL release already present in the config that is not "frozen" (see below), because new CVEs are disclosed continuously and a release scanned last month may have new CRITICAL/HIGH CVEs today. Adding new releases and re-scanning existing ones are two independent outcomes of a run — a run with zero new releases can still produce CVE updates.
* Determining "frozen": A release is frozen (skip it) ONLY when it holds 5 CRITICAL CVEs. You CANNOT determine this from the config alone: the `cves` field does not record severity, and entries are padded with HIGH CVEs to reach a total of 5. So a release listing 5 CVEs may still have fewer than 5 CRITICAL. Frozen status is tracked in the CVE Severity Tracking File (see below), NOT inferred from the config. Re-scan every non-EOL release that the tracking file does not mark as frozen, including those already listing 5 CVEs, and let the scan decide (promote newly-found CRITICAL CVEs above HIGH ones, keeping the total at 5).

### CVE Severity Tracking File
Because the config cannot record CVE severity, maintain a companion tracking file so future runs can skip releases already holding 5 CRITICAL CVEs (avoiding an expensive full re-scan every time).
- **Location:** `cve-severity-tracking.json` in this skill's workspace directory (alongside this skill file). It is a LOCAL file and is NOT committed to the upgrade-responders PR.
- **Schema:** each CVE is stored with the highest-priority image it appears in (see "CVE Ordering & Image Priority"), so the config CVE ordering can be recomputed WITHOUT re-scanning. Lists are stored already ordered (image priority, then CVE ID).
  ```json
  {
    "lastUpdated": "YYYY-MM-DD",
    "releases": {
      "v1.36.2+rke2r1": {
        "scannedAt": "YYYY-MM-DD",
        "critical": [{"id": "CVE-...", "image": "hardened-kubernetes"}],
        "high": [{"id": "CVE-...", "image": "rke2-runtime"}],
        "frozen": false
      }
    }
  }
  ```
- **`frozen`** is `true` iff `critical` has 5 or more entries. A frozen release is skipped by step 4 on subsequent runs.
- **Usage each run:** (1) Load the file if it exists. (2) Skip scanning any release whose entry has `frozen: true`. (3) After scanning a release, upsert its entry (full CRITICAL and HIGH lists with image attribution, `scannedAt`, recomputed `frozen`). (4) If the file does not exist, treat every non-EOL release as needing a scan (this bootstraps the file).
* Handling Multi-Releases: If a month has multiple releases for the same version (e.g., v1.35.5+rke2r1 and v1.35.5+rke2r2), treat them as two entirely separate releases.

### CVE Ordering & Image Priority
When a release has more CVEs than the 5-slot limit, WHICH CVEs are kept matters. CVEs are ranked by the **most important image** they appear in, so vulnerabilities in core components take the 5 slots ahead of peripheral ones.
- **Ranking of a CVE** = the priority of the highest-priority image in which trivy reports that CVE. Ties (same image priority) break by CVE ID ascending.
- **Final `cves` string** = all CRITICAL CVEs (ordered by this ranking) first, then HIGH CVEs (same ranking) to fill up to 5 total.
- **Image priority (most important first):**
  1. `rke2-runtime`
  2. `hardened-kubernetes`
  3. `hardened-etcd`
  4. `mirrored-pause`
  5. `hardened-coredns`
  6. `klipper-helm`
  7. `hardened-k8s-metrics-server`
  8. `hardened-traefik`
  9. `rke2-cloud-provider`
  10. `klipper-lb`
  11. `hardened-dns-node-cache`
  12. `hardened-calico`
  13. `hardened-flannel`
  14. `hardened-snapshot-controller`
  15. `hardened-cluster-autoscaler`
  16. `hardened-addon-resizer`
- Any image not in this list is treated as lowest priority (ranked after all listed images), then by CVE ID.
- Match images by their short name: `ref.split('/')[-1].split(':')[0]` (e.g. `docker.io/rancher/hardened-etcd:v3.6.12-...` -> `hardened-etcd`).


### Step-by-Step Procedure

1 - Clone & Checkout (Git Setup)
* Clone the repository https://github.com/rancher/upgrade-responders and checkout the staging branch.

2 - Analyze Current Releases (Delta Identification)
* Fetch the official RKE2 releases from https://github.com/rancher/rke2/releases.
* Compare them against the current upgrade-responder-response-config.yaml file to identify missing releases.
* Collect the releaseDate for each missing release.

3 - Process Missing Releases (Metadata Preparation)
* For each identified missing release: Map the tag to "v1.$MINOR" (e.g., minor version 34 becomes tag "v1.34"). and construct the releaseNotesURL (ensure percent-encoding is applied to the + sign, converting it to %2Br, e.g., v1.35.2%2Brke2r1).

4 - Scan for CVEs (Trivy & OpenVEX)
* Build the scan set = (all newly added releases from step 3) + (all existing non-EOL releases NOT marked `frozen` in the CVE Severity Tracking File). Do NOT limit this to missing releases — see "Re-scan Existing Releases" above. This step runs even when step 2 found zero missing releases.
* For each release in the scan set:
    ** Locate the rke2-images.linux-amd64.txt asset in the RKE2 release assets list.
    ** Download the Rancher OpenVEX suppression file: https://github.com/rancher/vexhub/raw/refs/heads/main/reports/rancher.openvex.json.
    ** Loop through each image reference in the text file and run:
    ** trivy image "$image" --vex rancher.openvex.json --severity CRITICAL,HIGH --format json
    ** Compile the results, recording for each CVE the highest-priority image it appears in. Order CVEs per "CVE Ordering & Image Priority": CRITICAL first (by image priority, then CVE ID), then fill remaining slots with HIGH CVEs (same ordering) until you reach a total of 5.
    ** Upsert the release's entry in the CVE Severity Tracking File: full `critical` and `high` CVE lists with image attribution, `scannedAt`, and recomputed `frozen`.

5 - Assign 'Latest' Tag (Final Config Polish)
* Identify the release in the config file with the highest minor number and highest patch number. Assign the tag ["latest"] to this specific release.

6 - Create Pull Request (Git Delivery)
* Create a new branch from staging with a descriptive name (e.g., `update-rke2-releases-YYYY-MM-DD`)
* Commit the updated upgrade-responder-response-config.yaml file to the new branch
* Push the new branch to origin
* Open a Pull Request from the new branch targeting the staging branch using `gh pr create` with a descriptive title and summary of changes
* Never commit or push directly to `staging`. All changes reach `staging` only through a Pull Request.

7 - Verify Staging Deployment & Promote to main
* After opening the staging PR, ASK THE USER to review and merge it into `staging`. Wait for the user to confirm the merge — do NOT proceed automatically.
* Once the user confirms the PR is merged, wait 2 minutes for the staging upgrade-responder to pick up the new config, then query the staging endpoint:
  ```bash
  curl -X POST https://rke2-security.version.rancher.kitchen/v1/checkupgrade \
    -d '{"appVersion": "v0.0.0", "extraInfo": {}}' | jq .
  ```
* Inspect the response. If it includes the changes from this run (the updated versions / CVE data), the staging deployment is confirmed working.
* Only then, cherry-pick the SAME commit onto a new branch created from `main`, and open a second Pull Request targeting `main` (with the same title/summary). Never commit or push directly to `main`; all changes reach `main` only through a Pull Request.
* If the response does NOT include the new changes, stop and report it — do not open the `main` PR.

8 - Remove the upgrade-responders Github project that was cloned locally

### Validation
Before declaring the task complete, verify that:

- The modified file is a valid ConfigMap **through all nested layers**. A plain
  YAML parse of the file is NOT sufficient — this file has three serialization
  layers: the file is YAML, `data."values.yaml"` is a string that is *itself*
  YAML, and `configMap.responseConfig` inside that is a string that is JSON.
  Fleet parses the inner layers, so a broken embedded block still passes a naive
  file-level parse. You MUST run the check below and it MUST print all three OK
  lines before declaring the task complete:

  ```bash
  python3 - <path-to-config.yaml> <<'EOF'
  import yaml, json, sys
  doc = yaml.safe_load(open(sys.argv[1]))
  assert doc["kind"] == "ConfigMap"
  inner = yaml.safe_load(doc["data"]["values.yaml"])          # layer 2: YAML-in-YAML
  resp  = json.loads(inner["configMap"]["responseConfig"])    # layer 3: JSON-in-YAML
  print("Layer 1 (ConfigMap YAML): OK")
  print("Layer 2 (data.values.yaml): OK")
  print(f"Layer 3 (responseConfig JSON): OK, {len(resp['versions'])} versions")
  EOF
  ```

- When editing the JSON block under `responseConfig: |`, keep every line
  indented consistently. In a YAML literal block (`|`), the first content line
  sets the required indentation — a mis-indented opening `{` breaks the whole
  block with `did not find expected key`.

- Exactly one release is tagged as "latest".
