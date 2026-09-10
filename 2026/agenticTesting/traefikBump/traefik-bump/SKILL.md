---
name: traefik-bump
description: Automates the process of bumping Traefik images/charts for K3s and RKE2. Use this skill when asked to perform a Traefik bump or update on K3s, RKE2, or rke2-charts, including creating master issues/PRs and backport issues/PRs.
---

# Traefik Bump Automation Skill

This skill automates the sweeping process of updating Traefik across K3s, RKE2, and `rke2-charts`. The entire process is triggered by providing two tags:
- **K3s Traefik tag** (e.g., `v3.7.13`)
- **RKE2 Traefik tag** (e.g., `v3.7.13-build20260909`)

---

## CRUCIAL MANDATE: NO AUTOMATIC MERGING & GIT IDENTITY
- **NEVER AUTOMERGE PRs:** Under no circumstances should this skill or any agent attempt to automatically merge any created Pull Requests (on K3s, RKE2, or `rke2-charts`). Your scope is strictly limited to creating the issues and Pull Requests.
- **MANUAL REVIEW ONLY:** All PRs must remain open to be reviewed, approved, and manually merged by human maintainers.
- **IF A STEP SAYS 'WAIT FOR MERGE':** You must pause, clearly present the link to the created PR to the user, and ask them to manually review and merge it. Do not attempt to run any `gh pr merge` or similar commands.
- **GIT IDENTITY CONFIGURATION:** Before making any commits, ensure that the local Git configuration uses the correct human identity and email (e.g., `git config user.name "Manuel Buil"` and `git config user.email "mbuil@suse.com"`) so that commits and `Signed-off-by` trailers have correct authorship.

---

## 1. K3s Automation Flow

Perform the following steps sequentially for K3s:

### Step 1.1: Create Master Issue (K3s)
Create an issue on `k3s-io/k3s` requesting a Traefik bump to the new K3s tag (`$K3S_TAG`).
- **Title**: `Bump Traefik` (or `Bump Traefik $K3S_TAG`)
- **Template / Body**:
  ```markdown
  K3s is bundling <PREVIOUS_VERSION> but there is a new patch version

  **Describe the solution you'd like**
  Bump to the new Traefik version: $K3S_TAG
  ```
- **CLI Command**:
  ```bash
  gh issue create --repo k3s-io/k3s --title "Bump Traefik" --body "K3s is bundling <PREVIOUS_VERSION> but there is a new patch version.

  **Describe the solution you'd like**
  Bump to the new Traefik version: $K3S_TAG"
  ```
  *(Retrieve and note the created master issue number, e.g., `#14327`)*

### Step 1.2: Create Master PR (K3s)
1. Clone or navigate to the `k3s` repository.
2. Checkout a new branch: `git checkout -b bump-traefik-$K3S_TAG`
3. Modify the Traefik tag in **`manifests/traefik.yaml`** to `$K3S_TAG`.
4. Commit the change: `git commit -s -m "Bump Traefik to $K3S_TAG"`
5. Push and create a Pull Request on `k3s-io/k3s` (targeting `master`/`main`):
   - **Title**: `Bump Traefik to $K3S_TAG`
   - **Body**:
     ```markdown
     **Proposed Changes**
     Bump Traefik to $K3S_TAG

     **Types of Changes**
     Version bump

     **Verification**
     Deploy K3s and verify the image tag

     **Linked Issues**
     Resolves #<MASTER_ISSUE_NUMBER>

     **User-Facing Change**
     Bump Traefik to $K3S_TAG
     ```
   - **CLI Command**:
     ```bash
     gh pr create --repo k3s-io/k3s --title "Bump Traefik to $K3S_TAG" --body "**Proposed Changes**
     Bump Traefik to $K3S_TAG

     **Types of Changes**
     Version bump

     **Verification**
     Deploy K3s and verify the image tag

     **Linked Issues**
     Resolves #<MASTER_ISSUE_NUMBER>

     **User-Facing Change**
     Bump Traefik to $K3S_TAG"
     ```
   *(Retrieve and note the master PR number, e.g., `#14604`)*

### Step 1.3: Ask for Backport Branches
Ask the user which release branches they want to backport the K3s bump to (e.g., `1.35`, `1.34`).

### Step 1.4: Create Backport Issues & PRs (K3s)
For each target backport branch (`$branch`):

#### A. Create Backport Issue:
- **Title**: `[Release-$branch] - Bump Traefik`
- **Labels**: `kind/backport`
- **Body**:
  ```markdown
  Backport fix for Bump Traefik

  * #<MASTER_ISSUE_NUMBER>
  ```
- **CLI Command**:
  ```bash
  gh issue create --repo k3s-io/k3s --title "[Release-$branch] - Bump Traefik" --label "kind/backport" --body "Backport fix for Bump Traefik

  * #<MASTER_ISSUE_NUMBER>"
  ```
  *(Retrieve and note the backport issue number, e.g., `#14375`)*

#### B. Create Backport PR:
1. Checkout and pull the release branch: `git checkout release-$branch && git pull`
2. Create a new branch: `git checkout -b bump-traefik-$K3S_TAG-$branch`
3. Apply the same modification to **`manifests/traefik.yaml`** to use `$K3S_TAG`.
4. Commit: `git commit -s -m "Bump Traefik to $K3S_TAG"`
5. Push and create the PR targeting `release-$branch`:
   - **Title**: `[Release-$branch] Bump Traefik $K3S_TAG` (or `[RELEASE-$branch] BUMP TRAEFIK $K3S_TAG`)
   - **Body**:
     ```markdown
     Backport: https://github.com/k3s-io/k3s/pull/<MASTER_PR_NUMBER>
     Issue: https://github.com/k3s-io/k3s/issues/<BACKPORT_ISSUE_NUMBER>
     ```
   - **CLI Command**:
     ```bash
     gh pr create --repo k3s-io/k3s --base "release-$branch" --title "[Release-$branch] Bump Traefik $K3S_TAG" --body "Backport: https://github.com/k3s-io/k3s/pull/<MASTER_PR_NUMBER>
     Issue: https://github.com/k3s-io/k3s/issues/<BACKPORT_ISSUE_NUMBER>"
     ```

---

## 2. RKE2 Automation Flow

Perform the following steps sequentially for RKE2:

### Step 2.1: Update `rke2-charts`
1. Clone or navigate to the `rke2-charts` repository.
2. Checkout a new branch: `git checkout -b bump-traefik-$RKE2_TAG`
3. Modify **`packages/rke2-traefik/package.yaml`**:
   - Increment the `packageVersion` by 1 (e.g., `01` -> `02`).
4. Modify **`packages/rke2-traefik/generated-changes/patch/values.yaml.patch`**:
   - Locate the Traefik image tag and update it to `$RKE2_TAG`.
5. Modify **`packages/rke2-traefik-1.34-1.36/package.yaml`**:
   - Increment the `packageVersion` by 1 (e.g., `11` -> `12`).
6. Modify **`packages/rke2-traefik-1.34-1.36/generated-changes/patch/values.yaml.patch`**:
   - Locate the Traefik image tag and update it to `$RKE2_TAG`.
7. Commit: `git commit -a -s -m "Bump Traefik to $RKE2_TAG"`
8. Push and create a Pull Request on `rancher/rke2-charts` targeting `main`:
   - **Title**: `Bump Traefik to $RKE2_TAG`
   - **Body**: `Bump Traefik image tag to $RKE2_TAG in rke2-traefik and rke2-traefik-1.34-1.36 packages.`
9. **Pause and Ask**: Present the PR link to the user and ask them to manually review and merge it. Do not attempt to automatically merge it yourself. Once the user has manually merged the PR, wait a few minutes for the CI to generate and publish the new chart version.

### Step 2.2: Identify New Chart Versions
Two separate chart versions are generated depending on the package used in `rke2-charts`:
1. **Main Chart Version (`$CHART_VERSION_MAIN`, e.g., `41.2.002`)**: Sourced from the **`rke2-traefik`** package. This is used for `master` and `1.37` release branches.
2. **Legacy Chart Version (`$CHART_VERSION_LEGACY`, e.g., `40.1.012`)**: Sourced from the **`rke2-traefik-1.34-1.36`** package. This is used for legacy release branches (`1.36`, `1.35`, and `1.34`).

Inspect the `rke2-charts` repository or ask the user to identify both chart versions before moving forward.

### Step 2.3: Create Master Issue (RKE2)
Create an issue on `rancher/rke2` requesting a Traefik bump.
- **Title**: `Bump Traefik to $K3S_TAG` (uses upstream K3s/upstream tag)
- **Body**:
  ```markdown
  There is a new Traefik version

  **Describe the solution you'd like**
  Bump to the newer version: $K3S_TAG
  ```
- **CLI Command**:
  ```bash
  gh issue create --repo rancher/rke2 --title "Bump Traefik to $K3S_TAG" --body "..."
  ```
  *(Retrieve and note the created RKE2 master issue number, e.g., `#11183`)*

### Step 2.4: Create Master PR (RKE2)
1. Clone or navigate to the `rke2` repository.
2. Checkout a new branch: `git checkout -b bump-traefik-$K3S_TAG`
3. Modify **`charts/chart_versions.yaml`**:
   - Locate references to `/charts/rke2-traefik.yaml` and `/charts/rke2-traefik-crd.yaml`.
   - Update their version to the newly identified main/modern chart version (**`$CHART_VERSION_MAIN`**).
4. Modify **`scripts/build-images`**:
   - Locate `${REGISTRY}/rancher/hardened-traefik:<OLD_TAG>` and replace with `${REGISTRY}/rancher/hardened-traefik:$RKE2_TAG`.
   - **Note**: In `master` (and `1.37`/`1.36`), this image is located in the section that generates **`images-core.txt`**.
5. Commit: `git commit -a -s -m "Bump Traefik to $K3S_TAG"`
6. Push and create a Pull Request on `rancher/rke2` targeting `master`:
   - **Title**: `Bump Traefik to $K3S_TAG`
   - **Body**:
     ```markdown
     **Proposed Changes**
     Bump Traefik to $K3S_TAG

     **Types of Changes**
     Version bump

     **Verification**
     Deploy RKE2 and verify the image tag

     **Linked Issues**
     Resolves #<RKE2_MASTER_ISSUE_NUMBER>

     **User-Facing Change**
     Bump Traefik to $K3S_TAG
     ```
   *(Retrieve and note the RKE2 master PR number, e.g., `#11179`)*

### Step 2.5: Ask for Backport Branches (RKE2)
Ask the user which release branches they want to backport the RKE2 bump to (e.g., `1.35`).

### Step 2.6: Create Backport Issues & PRs (RKE2)
For each target backport branch (`$branch`):

#### A. Create Backport Issue (RKE2):
- **Title**: `[Release-$branch] - Bump Traefik`
- **Labels**: `kind/backport`
- **Body**:
  ```markdown
  Backport fix for Bump Traefik to $K3S_TAG

  * #<RKE2_MASTER_ISSUE_NUMBER>
  ```
- **CLI Command**:
  ```bash
  gh issue create --repo rancher/rke2 --title "[Release-$branch] - Bump Traefik" --label "kind/backport" --body "Backport fix for Bump Traefik to $K3S_TAG

  * #<RKE2_MASTER_ISSUE_NUMBER>"
  ```
  *(Retrieve and note the RKE2 backport issue number, e.g., `#11195`)*

#### B. Create Backport PR (RKE2):
1. Checkout and pull the release branch: `git checkout release-$branch && git pull`
2. Create a new branch: `git checkout -b bump-traefik-$K3S_TAG-$branch`
3. Modify the same files (**`charts/chart_versions.yaml`** and **`scripts/build-images`**) to use `$RKE2_TAG` and the appropriate chart version:
   - **For `1.37`**: Locate the entries for `/charts/rke2-traefik.yaml` and `/charts/rke2-traefik-crd.yaml`, and update their versions using the main/modern chart version (**`$CHART_VERSION_MAIN`**).
   - **For `1.36`, `1.35`, and `1.34`**: Locate the entries for `/charts/rke2-traefik.yaml` and `/charts/rke2-traefik-crd.yaml` (which contain the line `package: rke2-traefik-1.34-1.36`), and update their versions using the legacy chart version (**`$CHART_VERSION_LEGACY`**).
   - **For `scripts/build-images`**:
     - **In `1.37` and `1.36`**: The `${REGISTRY}/rancher/hardened-traefik` image tag is located in the section that generates **`images-core.txt`**.
     - **In `1.35` and `1.34`**: The `${REGISTRY}/rancher/hardened-traefik` image tag is located in the section that generates **`images-traefik.txt`**.
     Update the tag to `$RKE2_TAG` in the appropriate section.
4. Commit: `git commit -a -s -m "Bump Traefik $RKE2_TAG"`
5. Push and create the PR targeting `release-$branch` on `rancher/rke2`:
   - **Title**: `[Release-$branch] Bump Traefik $K3S_TAG` (or `[RELEASE $branch] BUMP TRAEFIK $K3S_TAG`)
   - **Body**:
     ```markdown
     Backport: https://github.com/rancher/rke2/pull/<RKE2_MASTER_PR_NUMBER>
     Issue: https://github.com/rancher/rke2/issues/<RKE2_BACKPORT_ISSUE_NUMBER>
     ```
   - **CLI Command**:
     ```bash
     gh pr create --repo rancher/rke2 --base "release-$branch" --title "[Release-$branch] Bump Traefik $K3S_TAG" --body "Backport: https://github.com/rancher/rke2/pull/<RKE2_MASTER_PR_NUMBER>
     Issue: https://github.com/rancher/rke2/issues/<RKE2_BACKPORT_ISSUE_NUMBER>"
     ```
