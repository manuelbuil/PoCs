## Sync rke2-docs and rke2-product-docs
There are two documentation projects which are very similar:
* https://github.com/rancher/rke2-docs
* https://github.com/rancher/rke2-product-docs

The latter includes also information for RKE2 customers and the format is ASCII

The task is to cherry-pick commits from https://github.com/rancher/rke2-docs to this local project (rke2-product-docs)

### Procedure
1. Fetch all commits from https://github.com/rancher/rke2-docs from the last 2 weeks
2. Filter out: dependabot commits, merge commits that are already covered by individual commits
3. Verify if they were already ported in https://github.com/rancher/rke2-product-docs
4. If they were ported, do nothing.
5. If they were not ported, cherry-pick each of them and adjust it to rke2-product-docs (ascii, etc. Check "known edge cases")
6. Do not include this CLAUDE.md in the commit 
7. Create a different branch in the local project for each of the unsync commits
8. Start the commit with [sync rke2-docs]
9. Explain in the commit what changed and add a link to the PR from rke2-docs
10. Push the branches to the Github project https://github.com/manuelbuil/rke2-product-docs so that I can later create a PR in the upstream project

### Prerequisites
- RKE2_IMAGES_BASE_URL environment variable must be set

### Validation
Check if the job completely successfully.
- A branch was created for each of the commits

### Known Edge Cases
- rke2-product-docs is written in ASCII and generated with Antora whereas rke2-docs uses Markdown and Docusaurus 2 as generator
- rke2-product-docs includes a few lines in the beggining of each file. One if revdate, which should be updated when there is a change in that page
- rke2-product-docs support two languages (en, zh). When a page changes in "en", there should be a change in "zh" as well. There is no need to translate, it could be English as well.
- rke2-product-docs includes some specific information for RKE2 Prime customers, for example how to install. That information must be kept in rke2-product-docs
- when syncing release notes, do not add an extra column
- when syncing release notes, determine the ingress-nginx version for each RKE2 release:
  - IMPORTANT: Check if the RKE2_IMAGES_BASE_URL environment variable is set. If not, warn the user and stop.
  - For RKE2 v1.36+: fetch ${RKE2_IMAGES_BASE_URL}/rke2/{version}/rke2-images-ingress-nginx.linux-amd64.txt
  - For RKE2 < v1.36: fetch ${RKE2_IMAGES_BASE_URL}/rke2/{version}/rke2-images-all.linux-amd64.txt
  - Extract the version tag from the `nginx-ingress-controller` line
  - Note: ingress-nginx version info is not part of rke2-docs

# Ignore this: git submodule update --init --recursive --force
