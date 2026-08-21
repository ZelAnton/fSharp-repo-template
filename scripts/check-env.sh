#!/usr/bin/env bash
#
# Checks this machine can build and test an F# (.NET) project before you
# initialize the template (POSIX counterpart of check-env.ps1 — use whichever
# matches your shell; both do the same thing).
#
# Asks the .NET host to resolve the SDK configuration pinned in global.json.
# Exits 0 when ready; if a required tool is missing or the SDK configuration
# cannot be resolved, it prints per-OS install commands and exits 1 — install
# what it names, then re-run.
# (Fantomas is a local tool restored by `dotnet tool restore`, not a separate
# environment prerequisite, so it is not checked here.)
#
# Usage: bash ./scripts/check-env.sh

set -euo pipefail
case "${1:-}" in -h|--help) sed -n '2,13p' "$0"; exit 0 ;; esac

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
global_json="$repo_root/global.json"
global_json_missing=false
configured_sdk_version=""
configured_sdk_major=""
configuration_error=""

problems=()
echo "==> Checking environment for F# (.NET) development"

# Required: the .NET SDK (it bundles the F# compiler and `dotnet test`).
if [ ! -f "$global_json" ]; then
  global_json_missing=true
  problems+=("the SDK configuration file '$global_json' is missing")
else
  global_json_text="$(tr '\n' ' ' < "$global_json")"
  if [[ "$global_json_text" =~ \"sdk\"[[:space:]]*:[[:space:]]*\{([^}]*)\} ]]; then
    sdk_object="${BASH_REMATCH[1]}"
    if [[ "$sdk_object" =~ \"version\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
      configured_sdk_version="${BASH_REMATCH[1]}"
    else
      configuration_error='global.json must define sdk.version'
    fi
  else
    configuration_error='global.json must define sdk.version'
  fi

  if [ -z "$configuration_error" ] && [[ ! "$configured_sdk_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]]; then
    configuration_error="sdk.version '$configured_sdk_version' is not a valid SDK version"
  fi

  if [ -z "$configuration_error" ]; then
    configured_sdk_major="${configured_sdk_version%%.*}"
  fi
fi

if [ -n "$configuration_error" ]; then
  problems+=("invalid SDK configuration in '$global_json': $configuration_error")
elif [ "$global_json_missing" = false ]; then
  if ! command -v dotnet >/dev/null 2>&1; then
    problems+=("the .NET SDK ('dotnet' is not on PATH)")
  elif resolved_sdk="$(cd "$repo_root" && dotnet --version 2>&1)"; then
    echo "    .NET SDK $resolved_sdk resolved from global.json"
  else
    problems+=("the SDK configuration in '$global_json' could not be resolved by dotnet")
    while IFS= read -r line; do
      echo "    $line"
    done <<< "$resolved_sdk"
  fi
fi

# Soft: git drives the init defaults (author/email) and the VCS workflow.
command -v git >/dev/null 2>&1 || \
  echo "    note: git is not on PATH — init falls back to placeholder author/email."

if [ ${#problems[@]} -eq 0 ]; then
  echo
  echo "Environment ready. Next: bash ./scripts/init.sh --project-name ..."
  exit 0
fi

echo
echo "Environment NOT ready. Missing:"
for p in "${problems[@]}"; do echo "  - $p"; done
echo
if [ -n "$configured_sdk_version" ]; then
  echo "Install the .NET SDK $configured_sdk_version, then re-run this check:"
  echo "  Windows : winget install Microsoft.DotNet.SDK.$configured_sdk_major"
  echo "  macOS   : brew install --cask dotnet-sdk"
  echo "  Linux   : see https://learn.microsoft.com/dotnet/core/install/linux"
else
  echo "Fix the SDK configuration in '$global_json', then re-run this check."
fi
exit 1
