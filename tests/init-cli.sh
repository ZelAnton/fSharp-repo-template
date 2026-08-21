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

run_success_case 'year-upper-boundary' '2147483647' \
  --project-name Acme.Widgets --year 2147483647 --keep-script
run_success_case 'year-lower-boundary' '-2147483648' \
  --project-name Acme.Widgets --year -2147483648 --keep-script
run_failure_case 'year-above-upper-boundary' "invalid --year '2147483648'" \
  --project-name Acme.Widgets --year 2147483648 --keep-script
run_failure_case 'year-below-lower-boundary' "invalid --year '-2147483649'" \
  --project-name Acme.Widgets --year -2147483649 --keep-script

printf 'Bash initializer CLI regression checks passed.\n'
