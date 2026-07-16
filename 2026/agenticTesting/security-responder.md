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
* CVE Limit: Once a release entry contains 5 CVEs, do not scan it or update its CVE list further.
* Handling Multi-Releases: If a month has multiple releases for the same version (e.g., v1.35.5+rke2r1 and v1.35.5+rke2r2), treat them as two entirely separate releases.


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
* If a release has fewer than 5 CVEs:
    ** Locate the r2ke-images.linux-amd64.txt asset in the RKE2 release assets list.
    ** Download the Rancher OpenVEX suppression file: https://github.com/rancher/vexhub/raw/refs/heads/main/reports/rancher.openvex.json.
    ** Loop through each image reference in the text file and run:
    ** trivy image "$image" --vex rancher.openvex.json --severity CRITICAL,HIGH --format json
    ** Compile the results. Write any CRITICAL CVEs first. If you have fewer than 5, fill the remaining slots with HIGH CVEs until you reach a total of 5.

5 - Assign 'Latest' Tag (Final Config Polish)
* Identify the release in the config file with the highest minor number and highest patch number. Assign the tag ["latest"] to this specific release.

6 - Create Pull Request (Git Delivery)
* Create a new branch from staging with a descriptive name (e.g., `update-rke2-releases-YYYY-MM-DD`)
* Commit the updated upgrade-responder-response-config.yaml file to the new branch
* Push the new branch to origin
* Open a Pull Request from the new branch targeting the staging branch using `gh pr create` with a descriptive title and summary of changes

### Validation
Before declaring the task complete, verify that:

- The modified file parses as valid Kubernetes ConfigMap
- Exactly one release is tagged as "latest".
