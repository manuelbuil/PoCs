## Sync rke2-docs and rke2-product-docs
There are two documentation projects which are very similar:
* https://github.com/rancher/rke2-docs
* https://github.com/rancher/rke2-product-docs

The latter includes also information for RKE2 customers and the format is ASCII

The task is to cherry-pick commits from https://github.com/rancher/rke2-docs to this local project (rke2-product-docs)

### Procedure
1. Inspect https://github.com/rancher/rke2-docs commit messages during the last week
2. Verify if they were already ported in https://github.com/rancher/rke2-product-docs
3. If they were ported, do nothing.
4. If they were not ported, cherry-pick each of them and adjust it to rke2-product-docs (ascii, etc. Check "known edge cases")
5. Create a different branch in the local project for each of the unsync commits
6. Push the branches to the Github project https://github.com/manuelbuil/rke2-product-docs so that I can later create a PR in the upstream project

### Validation
Check if the job completely successfully.
- A branch was created for each of the commits

### Known Edge Cases
- rke2-product-docs is written in ASCII and generated with Antora whereas rke2-docs uses Markdown and Docusaurus 2 as generator
- rke2-product-docs includes a few lines in the beggining of each file. One if revdate, which should be updated when there is a change in that page
- rke2-product-docs support two languages (en, zh). When a page changes in "en", there should be a change in "zh" as well. There is no need to translate, it could be English as well.
- rke2-product-docs includes some specific information for RKE2 Prime customers, for example how to install. That information must be kept in rke2-product-docs
