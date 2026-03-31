#!/usr/bin/env bash
# publish_modules.sh
# Publishes Terraform modules to JFrog Artifactory Terraform registry.
#
# Required environment variables (injected by the pipeline):
#   VERSION        - the computed module version tag
#   JFROG_REPO     - target JFrog repository name
#   RELEASE_BRANCH - branch name that triggers a release publish (e.g. main)
#   GITHUB_REF_NAME - current branch name (set automatically by GitHub Actions)
set -euo pipefail

# ── Constants ──
NAMESPACE="odedwh"
PROVIDER="aws"

# ── Counters ──
upload_count=0
skip_count=0

# ── publish_module(source_dir, module_name) ──
# Checks for duplicate on release branch, stages module in a temp dir,
# writes the JFrog CLI project config, and publishes via jfrog tf p.
publish_module() {
  local source_dir="$1"
  local module_name="$2"
  echo "Publishing: ${module_name} v${VERSION}"

  # On release branch only: skip if this version already exists in JFrog
  if [[ "${GITHUB_REF_NAME}" == "${RELEASE_BRANCH}" ]]; then
    local check_path="${JFROG_REPO}/${NAMESPACE}/${module_name}/${PROVIDER}/${VERSION}/*"
    existing=$(jfrog rt s --server-id=artifactory-server "${check_path}")
    if [[ -n "$existing" && "$existing" != "[]" ]]; then
      echo "SKIP: ${module_name} v${VERSION} already exists."
      skip_count=$((skip_count + 1))
      return
    fi
  fi

  # Stage module files in a temp directory
  local temp_dir
  temp_dir=$(mktemp -d)
  local publish_dir="${temp_dir}/${module_name}"
  mkdir -p "${publish_dir}"
  cp -a "${source_dir}/." "${publish_dir}/"

  # Write JFrog CLI project config one level above publish_dir
  # so it is not bundled inside the uploaded module zip
  mkdir -p "${temp_dir}/.jfrog/projects"
  printf '%s\n' \
    "version: 1" \
    "type: terraform" \
    "resolver:" \
    "  serverId: artifactory-server" \
    "  repo: ${JFROG_REPO}" \
    "deployer:" \
    "  serverId: artifactory-server" \
    "  repo: ${JFROG_REPO}" \
    > "${temp_dir}/.jfrog/projects/terraform.yaml"

  # Publish the module to JFrog Terraform registry
  pushd "${publish_dir}" > /dev/null
  jfrog tf p \
    --namespace="${NAMESPACE}" \
    --provider="${PROVIDER}" \
    --tag="${VERSION}"
  popd > /dev/null
#Once activity is done, clean up the temp directory
  rm -rf "${temp_dir}"
  upload_count=$((upload_count + 1))
  echo "Published: ${module_name} v${VERSION}"
}

# ── Main: iterate over all modules in modules/ ──
# If a module directory contains .tf files directly, publish it as-is.
# Otherwise treat subdirectories as individual sub-modules.
for module_dir in modules/*/; do
  module_name=$(basename "${module_dir}")
  if ls "${module_dir}"*.tf 1>/dev/null 2>&1; then
    publish_module "${module_dir}" "${module_name}"
  else
    for submodule_dir in "${module_dir}"*/; do
      submodule_name=$(basename "${submodule_dir}")
      publish_module "${submodule_dir}" "${module_name}-${submodule_name}"
    done
  fi
done

# ── Summary to show uploaded vs skipped modules ──
echo "Done: ${upload_count} published, ${skip_count} skipped."
if [[ ${upload_count} -eq 0 && ${skip_count} -eq 0 ]]; then
  echo "ERROR: No modules found to publish."
  exit 1
fi
