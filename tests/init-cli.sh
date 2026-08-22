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

run_collision_case() {
  local name="$1"
  local checkout="$test_root/$name"
  mkdir -p "$checkout"
  (
    cd "$repo_root"
    tar --exclude='./.git' --exclude='*/bin' --exclude='*/obj' -cf - .
  ) | (
    cd "$checkout"
    tar -xf -
  )
  mkdir -p "$checkout/src/Acme.Widgets"
  : > "$checkout/Acme.Widgets.slnx"

  local before
  before="$(snapshot "$checkout")"

  local output status
  set +e
  output="$(cd "$checkout" && bash scripts/init.sh --project-name Acme.Widgets --keep-script 2>&1)"
  status=$?
  set -e

  [ "$status" -ne 0 ] || {
    printf 'expected collision failure for %s\n%s\n' "$name" "$output" >&2
    return 1
  }
  printf '%s\n' "$output" | grep -F -- 'generated path collision' >/dev/null || {
    printf 'missing collision diagnostic for %s: %s\n%s\n' "$name" "$output" >&2
    return 1
  }
  [ "$before" = "$(snapshot "$checkout")" ] || {
    printf 'initializer mutated the checkout for %s\n' "$name" >&2
    return 1
  }
}

run_settings_conflict_case() {
  local name="$1"
  local checkout="$test_root/$name"
  mkdir -p "$checkout"
  (cd "$repo_root" && tar --exclude='./.git' --exclude='*/bin' --exclude='*/obj' -cf - .) | (cd "$checkout" && tar -xf -)
  local settings="$checkout/.claude/settings.json"
  local expected='{"permissions":{"allow":["Bash(custom)"]}}'
  printf '%s' "$expected" > "$settings"
  local before output status
  before="$(snapshot "$checkout")"
  set +e
  output="$(cd "$checkout" && bash scripts/init.sh --project-name Acme.Widgets --keep-script 2>&1)"
  status=$?
  set -e
  [ "$status" -ne 0 ] || { printf 'expected settings conflict failure for %s\n%s\n' "$name" "$output" >&2; return 1; }
  printf '%s\n' "$output" | grep -F -- "refusing to overwrite existing local '.claude/settings.json'" >/dev/null || {
    printf 'missing settings conflict diagnostic for %s: %s\n' "$name" "$output" >&2
    return 1
  }
  [ "$(cat "$settings")" = "$expected" ] || { printf 'local settings changed for %s\n' "$name" >&2; return 1; }
  [ -f "$checkout/.claude/settings.json.template" ] || { printf 'settings template was removed for %s\n' "$name" >&2; return 1; }
  [ "$before" = "$(snapshot "$checkout")" ] || {
    printf 'initializer mutated the checkout for %s\n' "$name" >&2
    return 1
  }
}

run_settings_symlink_case() {
  local name="$1"
  local checkout="$test_root/$name"
  mkdir -p "$checkout"
  (cd "$repo_root" && tar --exclude='./.git' --exclude='*/bin' --exclude='*/obj' -cf - .) | (cd "$checkout" && tar -xf -)
  local settings="$checkout/.claude/settings.json"
  ln -s "$checkout/.claude/missing-settings-target" "$settings"
  local output status
  set +e
  output="$(cd "$checkout" && bash scripts/init.sh --project-name Acme.Widgets --keep-script 2>&1)"
  status=$?
  set -e
  [ "$status" -ne 0 ] || { printf 'expected dangling settings link failure for %s\n%s\n' "$name" "$output" >&2; return 1; }
  printf '%s\n' "$output" | grep -F -- "refusing to overwrite existing local '.claude/settings.json'" >/dev/null || {
    printf 'missing dangling-link diagnostic for %s: %s\n' "$name" "$output" >&2
    return 1
  }
  [ -L "$settings" ] || { printf 'dangling settings link was removed for %s\n' "$name" >&2; return 1; }
  [ -f "$checkout/.claude/settings.json.template" ] || { printf 'settings template was removed for %s\n' "$name" >&2; return 1; }
}

run_settings_race_case() {
  local name="$1"
  local checkout="$test_root/$name"
  local fake_bin="$test_root/$name-fake-bin"
  mkdir -p "$checkout" "$fake_bin"
  (cd "$repo_root" && tar --exclude='./.git' --exclude='*/bin' --exclude='*/obj' -cf - .) | (cd "$checkout" && tar -xf -)
  local fake_ln="$fake_bin/ln"
  cat > "$fake_ln" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "$#" -eq 4 ] && [ "$1" = '-T' ] && [ "$2" = '--' ]; then
  printf '%s' '{"permissions":{"allow":["Bash(race-created)"]}}' > "$4"
fi
exec "$REAL_LN" "$@"
EOF
  chmod +x "$fake_ln"
  local before output status real_ln
  before="$(snapshot "$checkout")"
  real_ln="$(command -v ln)"
  set +e
  output="$(cd "$checkout" && REAL_LN="$real_ln" PATH="$fake_bin:$PATH" bash scripts/init.sh --project-name Acme.Widgets --keep-script 2>&1)"
  status=$?
  set -e
  [ "$status" -ne 0 ] || { printf 'expected no-clobber failure for %s\n%s\n' "$name" "$output" >&2; return 1; }
  printf '%s\n' "$output" | grep -F -- "refusing to overwrite existing local '.claude/settings.json'" >/dev/null || {
    printf 'missing no-clobber diagnostic for %s: %s\n' "$name" "$output" >&2
    return 1
  }
  [ "$before" = "$(snapshot "$checkout")" ] || {
    printf 'initializer mutated the checkout for %s\n' "$name" >&2
    return 1
  }
  [ -f "$checkout/.claude/settings.json.template" ] || { printf 'settings template was removed for %s\n' "$name" >&2; return 1; }
  [ ! -e "$checkout/.claude/settings.json" ] && [ ! -L "$checkout/.claude/settings.json" ] || {
    printf 'race-created settings entry survived rollback for %s\n' "$name" >&2
    return 1
  }
}

run_rollback_case() {
  local name="$1" boundary="$2"
  local checkout="$test_root/$name"
  mkdir -p "$checkout"
  (cd "$repo_root" && tar --exclude='./.git' --exclude='*/bin' --exclude='*/obj' -cf - .) | (cd "$checkout" && tar -xf -)
  local before output status
  before="$(snapshot "$checkout")"
  set +e
  output="$(cd "$checkout" && TEMPLATE_INIT_FAIL_AT="$boundary" bash scripts/init.sh --project-name Acme.Widgets --keep-script 2>&1)"
  status=$?
  set -e
  [ "$status" -ne 0 ] || { printf 'expected rollback failure for %s\n%s\n' "$name" "$output" >&2; return 1; }
  printf '%s\n' "$output" | grep -F -- 'rolled back' >/dev/null || { printf 'missing rollback diagnostic for %s\n%s\n' "$name" "$output" >&2; return 1; }
  [ "$before" = "$(snapshot "$checkout")" ] || { printf 'rollback changed checkout for %s\n' "$name" >&2; return 1; }
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
  printf '%s\n' 'printf "%s\\n" "__Author__"' > "$checkout/metadata.sh"

  (cd "$checkout" && bash scripts/init.sh \
    --project-name Acme.Widgets \
    --author "$author" \
    --author-email 'dev+tag@example.com' \
    --github-owner acme-tools \
    --description 'Widget toolkit' \
    --year 2026 \
    --keep-script >/dev/null)

  python3 - "$checkout" "$author" <<'PY'
import pathlib
import sys
import xml.etree.ElementTree as ET

root = pathlib.Path(sys.argv[1])
author = sys.argv[2]
assert (root / "metadata.json").read_text().rstrip("\n") == '{"author":"__Author__"}'
assert (root / "metadata.yaml").read_text().rstrip("\n") == 'value: "__Author__"'
assert (root / "metadata.py").read_text().rstrip("\n") == 'value = "__Author__"'
assert (root / "src/Acme.Widgets/Acme.Widgets.fsproj").exists()
release_scenarios = (root / "tests" / "release-workflow.scenarios.py").read_text()
assert '"Acme.Widgets"' in release_scenarios
assert '"__ProjectName__"' not in release_scenarios
assert ET.parse(root / "src/Acme.Widgets/Acme.Widgets.fsproj").findtext("PropertyGroup/Authors") == author
PY
  grep -F -- 'printf "%s\\n" "__Author__"' "$checkout/metadata.sh" >/dev/null || {
    printf 'untracked shell file was rewritten for %s\n' "$name" >&2
    return 1
  }
  grep -F -- 'git config user.name "O\"Reilly \\Program Files\\Acme\\\"quoted\"\\bin & Sons; \$HOME \`id\`"' \
    "$checkout/.github/workflows/release.yml" >/dev/null || {
    printf 'workflow shell context was not escaped for %s\n' "$name" >&2
    return 1
  }
}

run_scope_case() {
  local name="$1"
  local checkout="$test_root/$name"
  mkdir -p "$checkout"
  (
    cd "$repo_root"
    tar --exclude='./.git' --exclude='*/bin' --exclude='*/obj' -cf - .
  ) | (
    cd "$checkout"
    tar -xf -
  )

  mkdir -p "$checkout/local-state"
  printf '%s\n' 'untracked __Author__ must stay unchanged' > "$checkout/local-state/notes.md"
  printf 'prefix\0__Author__\377suffix' > "$checkout/local-state/payload.bin"
  local text_before binary_before
  text_before="$(cat "$checkout/local-state/notes.md")"
  binary_before="$(sha256sum "$checkout/local-state/payload.bin" | cut -d' ' -f1)"

  (cd "$checkout" && bash scripts/init.sh --project-name Acme.Widgets --author 'Generated Author' --keep-script >/dev/null)

  [ "$(cat "$checkout/local-state/notes.md")" = "$text_before" ] || {
    printf 'untracked text file was rewritten for %s\n' "$name" >&2
    return 1
  }
  [ "$(sha256sum "$checkout/local-state/payload.bin" | cut -d' ' -f1)" = "$binary_before" ] || {
    printf 'untracked binary file was rewritten for %s\n' "$name" >&2
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
control_author_newline='bad
name'
run_failure_case 'control-author-newline' 'metadata values must not contain control characters' \
  --project-name Acme.Widgets --author "$control_author_newline"
control_author_tab=$'bad\tname'
run_failure_case 'control-author-tab' 'metadata values must not contain control characters' \
  --project-name Acme.Widgets --author "$control_author_tab"
control_author_carriage_return=$'bad\rname'
run_failure_case 'control-author-carriage-return' 'metadata values must not contain control characters' \
  --project-name Acme.Widgets --author "$control_author_carriage_return"
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
run_collision_case 'generated-name-collision'
run_settings_conflict_case 'settings-conflict'
run_settings_symlink_case 'dangling-settings-link'
run_settings_race_case 'settings-race'
run_rollback_case 'rollback-after-rename' 'apply-path-rename'
run_rollback_case 'rollback-after-settings' 'apply-settings-activation'
run_rollback_case 'rollback-during-cleanup' 'cleanup'
run_context_case 'encoded-metadata'
run_scope_case 'known-text-scope'

printf 'Bash initializer CLI regression checks passed.\n'
