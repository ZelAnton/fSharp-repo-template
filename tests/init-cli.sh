#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/fsharp-repo-template-init.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

snapshot() {
  local checkout="$1"
  (
    cd "$checkout"
    find . \( -path './.git' -o -path '*/bin' -o -path '*/obj' \) -prune -o \
      -type f -exec cksum {} \; | LC_ALL=C sort
  )
}

run_failure_case() {
  local name="$1"
  local expected="$2"
  shift 2

  local checkout="$test_root/$name"
  mkdir -p "$checkout"
  (
    cd "$repo_root"
    tar --exclude='./.git' --exclude='*/bin' --exclude='*/obj' -cf - .
  ) | (
    cd "$checkout"
    tar -xf -
  )

  local before
  before="$(snapshot "$checkout")"

  local output status
  set +e
  output="$(cd "$checkout" && bash scripts/init.sh "$@" 2>&1)"
  status=$?
  set -e

  [ "$status" -ne 0 ] || {
    printf 'expected failure for %s\n%s\n' "$name" "$output" >&2
    return 1
  }
  printf '%s\n' "$output" | grep -F -- "$expected" >/dev/null || {
    printf 'missing diagnostic for %s: %s\n%s\n' "$name" "$expected" "$output" >&2
    return 1
  }

  [ "$before" = "$(snapshot "$checkout")" ] || {
    printf 'initializer mutated the checkout for %s\n' "$name" >&2
    return 1
  }
}

run_success_case() {
  local name="$1"
  local expected_year="$2"
  shift 2

  local checkout="$test_root/$name"
  mkdir -p "$checkout"
  (
    cd "$repo_root"
    tar --exclude='./.git' --exclude='*/bin' --exclude='*/obj' -cf - .
  ) | (
    cd "$checkout"
    tar -xf -
  )

  local output
  output="$(cd "$checkout" && bash scripts/init.sh "$@" 2>&1)"
  printf '%s\n' "$output" | grep -F "Done. Next steps:" >/dev/null || {
    printf 'missing success output for %s: %s\n' "$name" "$output" >&2
    return 1
  }
  grep -F "Copyright (c) $expected_year" "$checkout/LICENSE" >/dev/null || {
    printf 'year was not written for %s\n' "$name" >&2
    return 1
  }
}

run_context_case() {
  local name="$1"
  local checkout="$test_root/$name"
  local author='O"Reilly \Program Files\Acme\"quoted"\bin & Sons; $HOME `id`'
  mkdir -p "$checkout"
  (
    cd "$repo_root"
    tar --exclude='./.git' --exclude='*/bin' --exclude='*/obj' -cf - .
  ) | (
    cd "$checkout"
    tar -xf -
  )
  printf '%s\n' '{"author":"__Author__"}' > "$checkout/metadata.json"
  printf '%s\n' 'value: "__Author__"' > "$checkout/metadata.yaml"
  printf '%s\n' 'value = "__Author__"' > "$checkout/metadata.py"
  printf '%s\n' 'printf "%%s\\n" "__Author__"' > "$checkout/metadata.sh"

  (cd "$checkout" && bash scripts/init.sh \
    --project-name Acme.Widgets \
    --author "$author" \
    --author-email 'dev+tag@example.com' \
    --github-owner acme-tools \
    --description 'Widget toolkit' \
    --year 2026 \
    --keep-script >/dev/null)

  python3 - "$checkout" "$author" <<'PY'
import json
import pathlib
import sys
import xml.etree.ElementTree as ET

root = pathlib.Path(sys.argv[1])
author = sys.argv[2]
assert json.loads((root / "metadata.json").read_text())["author"] == author
expected_json = json.dumps(author, ensure_ascii=False)
assert (root / "metadata.yaml").read_text().rstrip("\n") == "value: " + expected_json
assert (root / "metadata.py").read_text().rstrip("\n") == "value = " + expected_json
assert ET.parse(root / "src/Acme.Widgets/Acme.Widgets.fsproj").findtext("Authors") == author
namespace = {}
exec(compile((root / "metadata.py").read_text(), str(root / "metadata.py"), "exec"), namespace)
assert namespace["value"] == author
PY
  [ "$(cd "$checkout" && bash metadata.sh)" = "$author" ] || {
    printf 'shell context did not preserve metadata for %s\n' "$name" >&2
    return 1
  }
  grep -F -- 'git config user.name "O\"Reilly \\Program Files\\Acme\\\"quoted\"\\bin & Sons; \$HOME \`id\`"' \
    "$checkout/.github/workflows/release.yml" >/dev/null || {
    printf 'workflow shell context was not escaped for %s\n' "$name" >&2
    return 1
  }
}

value_options=(--project-name --author --author-email --github-owner --description --year)
for option in "${value_options[@]}"; do
  if [ "$option" = '--project-name' ]; then
    run_failure_case "missing-${option#--}" "$option requires a value." "$option"
  else
    run_failure_case "missing-${option#--}" "$option requires a value." --project-name Acme.Widgets "$option"
  fi
done

for option in "${value_options[@]}"; do
  if [ "$option" = '--project-name' ]; then
    run_failure_case "option-like-${option#--}" "$option requires a value." "$option" --author
  else
    run_failure_case "option-like-${option#--}" "$option requires a value." \
      --project-name Acme.Widgets "$option" --keep-script
  fi
done

run_failure_case 'invalid-year' "invalid --year 'not-a-year'" \
  --project-name Acme.Widgets --year not-a-year
control_author='bad
name'
run_failure_case 'control-author' 'metadata values must not contain control characters' \
  --project-name Acme.Widgets --author "$control_author"
run_failure_case 'token-description' 'metadata values must not contain template tokens' \
  --project-name Acme.Widgets --description 'prefix__Author__suffix'
run_failure_case 'unsafe-owner' 'invalid --github-owner' \
  --project-name Acme.Widgets --github-owner 'acme;touch-pwned'

run_success_case 'year-upper-boundary' '2147483647' \
  --project-name Acme.Widgets --year 2147483647 --keep-script
run_success_case 'year-lower-boundary' '-2147483648' \
  --project-name Acme.Widgets --year -2147483648 --keep-script
run_failure_case 'year-above-upper-boundary' "invalid --year '2147483648'" \
  --project-name Acme.Widgets --year 2147483648 --keep-script
run_failure_case 'year-below-lower-boundary' "invalid --year '-2147483649'" \
  --project-name Acme.Widgets --year -2147483649 --keep-script
run_context_case 'encoded-metadata'

printf 'Bash initializer CLI regression checks passed.\n'
