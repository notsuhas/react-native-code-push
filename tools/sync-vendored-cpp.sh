#!/usr/bin/env bash
# sync-vendored-cpp.sh — refresh the vendored C++ sources under cpp/.
#
# Run this when bumping the pinned version of either upstream. Both
# projects are MIT-licensed and committed verbatim (no patches on top).
#
# Usage:
#   tools/sync-vendored-cpp.sh
#
# Inputs (env vars, all optional):
#   HDIFFPATCH_TAG    — git tag to clone, default v4.9.0
#   RN_UPDATE_REF     — react-native-update ref, default master
#   RN_UPDATE_REPO    — sibling clone path,
#                       default ../react-native-ota-updater/../react-native-update

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HDIFFPATCH_TAG="${HDIFFPATCH_TAG:-v4.9.0}"
RN_UPDATE_REPO="${RN_UPDATE_REPO:-${REPO_ROOT}/../react-native-update}"

echo "Repo root:        ${REPO_ROOT}"
echo "HDiffPatch tag:   ${HDIFFPATCH_TAG}"
echo "rn-update path:   ${RN_UPDATE_REPO}"
echo

# --- HDiffPatch -------------------------------------------------------------
echo "→ HDiffPatch ${HDIFFPATCH_TAG}"
rm -rf "${REPO_ROOT}/cpp/HDiffPatch"
git clone --depth 1 --branch "${HDIFFPATCH_TAG}" \
    https://github.com/sisong/HDiffPatch.git \
    "${REPO_ROOT}/cpp/HDiffPatch"
rm -rf "${REPO_ROOT}/cpp/HDiffPatch/.git" \
       "${REPO_ROOT}/cpp/HDiffPatch/.github"

# --- react-native-update patch_core ----------------------------------------
echo "→ patch_core (rn-update ${RN_UPDATE_REF:-master})"
if [[ ! -d "${RN_UPDATE_REPO}/cpp/patch_core" ]]; then
  echo "ERROR: ${RN_UPDATE_REPO}/cpp/patch_core does not exist." >&2
  echo "Clone https://github.com/reactnativecn/react-native-update next to this repo." >&2
  exit 1
fi

rm -rf "${REPO_ROOT}/cpp/patch_core"
mkdir -p "${REPO_ROOT}/cpp/patch_core/tests"

# Whitelist — keep this list in sync with cpp/patch_core/CMakeLists usage
# in android/app/src/main/cpp/CMakeLists.txt and the iOS .podspec glob.
files=(
  "archive_patch_core.cpp"
  "archive_patch_core.h"
  "patch_core.cpp"
  "patch_core.h"
  "state_core.cpp"
  "state_core.h"
)
for f in "${files[@]}"; do
  cp "${RN_UPDATE_REPO}/cpp/patch_core/${f}" "${REPO_ROOT}/cpp/patch_core/${f}"
done
cp "${RN_UPDATE_REPO}/cpp/patch_core/tests/patch_core_test.cpp" \
   "${REPO_ROOT}/cpp/patch_core/tests/"

# Sanity: rn-update's Android-specific bindings MUST NOT land here
forbidden=("patch_core_android.cpp" "update_core_android.cpp")
for f in "${forbidden[@]}"; do
  if [[ -e "${REPO_ROOT}/cpp/patch_core/${f}" ]]; then
    echo "ERROR: ${f} should not be vendored — we ship our own JNI." >&2
    exit 1
  fi
done

echo
echo "Vendoring complete. Update THIRD_PARTY_LICENSES.md if the tag changed."
echo "Don't forget to update the rnota worker's Dockerfile to the same"
echo "HDiffPatch tag — server hdiffz and client hpatchz must match."
