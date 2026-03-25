# my-pipeline.yaml — Documentation

## Overview

A manually triggered GitHub Actions pipeline that publishes Terraform modules to a JFrog Artifactory Terraform registry with proper indexing.

---

## Trigger

Manually triggered via `workflow_dispatch` with one input:

| Input | Options | Default |
|---|---|---|
| `jfrog_environment` | `non_prod`, `prod` | `prod` |

---

## Steps

### 1. Set environment variables
- Sets `JFROG_ACCESS_TOKEN` and `JFROG_REPO` based on the selected environment (`non_prod` or `prod`).
- Uses GitHub Secrets and Variables to keep credentials secure.

### 2. Checkout
- Clones the repository onto the runner to access `modules/` and the `VERSION` file.

### 3. Set up JFrog CLI
- Installs the JFrog CLI on the runner using `jfrog/setup-jfrog-cli@v4`.

### 4. Configure JFrog Server
- Registers the JFrog Artifactory server under the alias `artifactory-server` using the URL and access token.

### 5. Prepare artifact version
- Reads the version from the `VERSION` file at the repo root.
- Version is determined by the branch:

| Branch | Version Format | Example |
|---|---|---|
| `main` | `<base_version>` | `1.0.2` |
| Any other branch | `<base_version>-<branch-name>` | `1.0.2-feature-my-work` |

- Exports `VERSION` as an environment variable for the next step.

### 6. Publish Terraform modules to JFrog registry
- Iterates over every folder inside `modules/`.
- **Standard module** (has `.tf` files at root) → published as-is (e.g. `s3`).
- **Container module** (no `.tf` files at root) → each subfolder published as `<parent>-<child>`.
- For each module:
  - Creates a temporary staging directory.
  - Generates a `.jfrog/projects/terraform.yaml` config pointing to the target repo.
  - Runs `jfrog tf p` to index and publish the module into the JFrog Terraform registry.
- On `main`: skips publishing if the exact version already exists (prevents overwrites).
- Fails the pipeline if no modules were found or published.

---

## JFrog Registry Path Format

```
<JFROG_REPO>/<namespace>/<module_name>/<provider>/<version>/
```

Example:
```
my-tf-repo/odedwh/s3/aws/1.0.2/
```

---

## Required Secrets & Variables

| Name | Type | Description |
|---|---|---|
| `JFROG_NON_PROD_TOKEN` | Secret | Access token for non-prod JFrog |
| `JFROG_PROD_TOKEN` | Secret | Access token for prod JFrog |
| `JFROG_NON_PROD_REPO` | Variable | Non-prod repository name |
| `JFROG_PROD_REPO` | Variable | Prod repository name |
| `JFROG_URL` | Variable | JFrog Artifactory base URL |

---

## VERSION File

A plain text file at the repo root containing the base semantic version:

```
1.0.2
```
