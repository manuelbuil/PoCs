## Sync k3s-docs and k3s-product-docs
There are two documentation projects which are very similar:
* https://github.com/k3s-io/docs
* https://github.com/rancher/k3s-product-docs

The latter includes also information for K3s customers and the format is ASCII

The task is to cherry-pick commits from https://github.com/k3s-io/docs to this local project (k3s-product-docs)

### Procedure
1. Fetch all commits from https://github.com/k3s-io/docs from the last 2 weeks
2. Filter out: dependabot commits, merge commits that are already covered by individual commits
3. Verify if they were already ported in https://github.com/rancher/k3s-product-docs
4. If they were ported, do nothing.
5. If they were not ported, cherry-pick each of them and adjust it to k3s-product-docs (ascii, etc. Check "known edge cases")
6. Do not include this CLAUDE.md in the commit 
7. Create a different branch in the local project for each of the unsync commits
8. Start the commit with [sync k3s-docs]
9. Explain in the commit what changed and add a link to the PR from rke2-docs
10. Push the branches to the Github project https://github.com/manuelbuil/k3s-product-docs so that I can later create a PR in the upstream project

### Validation
Check if the job completely successfully.
- A branch was created for each of the commits

### Known Edge Cases
- k3s-product-docs is written in ASCII and generated with Antora whereas rke2-docs uses Markdown and Docusaurus 2 as generator
- k3s-product-docs includes a few lines in the beggining of each file. One if revdate, which should be updated when there is a change in that page
- k3s-product-docs supports multiple languages (en, de, es, fr, ja, pt, zh). Only change the English ("en") pages. The docs team takes care of translating changes into the other languages, so do NOT modify any non-English language directory.
- k3s-product-docs includes some specific information for K3S Prime customers, for example how to install. That information must be kept in k3s-product-docs
- when syncing release notes, do not add an extra column

# Ignore this: file with permissions .claude/settings.json
