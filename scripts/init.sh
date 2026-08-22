#!/usr/bin/env bash
#
# Initializes this template into a concrete F# project (POSIX counterpart of
# init.ps1 — use whichever matches your shell; both do the same thing).
#
# Replaces the placeholder tokens (__ProjectName__, __Author__, __AuthorEmail__,
# __GitHubOwner__, __Description__, __Year__) in file contents AND in file/folder
# names, then removes the template-only files (TEMPLATE.md,
# docs/AGENT-INIT-GUIDE.md) and — unless --keep-script — both initializers
# (init.sh and init.ps1).
#
# Usage:
#   bash ./scripts/init.sh --project-name Acme.Widgets \
#       [--author "Jane Doe"] [--author-email you@example.com] \
#       [--github-owner acme] [--description "Widget toolkit"] \
#       [--year 2026] [--keep-script]
#
# --project-name is required; the rest fall back to sensible defaults so the
# result always builds. Edit LICENSE / the .fsproj afterwards to refine them.

set -euo pipefail

# In bash >= 5.2 an unescaped '&' in a ${var//pat/repl} replacement is replaced
# by the matched text (controlled by 'patsub_replacement', on by default). The
# XML-escaped values below legitimately contain '&' (e.g. '&amp;'), so disable
# this so replacements are always literal. Guarded: the option — and the
# behaviour — don't exist on older bash, where literal substitution is the norm.
shopt -u patsub_replacement 2>/dev/null || true

project_name=""
author=""
author_email=""
github_owner=""
description=""
year=""
keep_script=0

die() { echo "error: $*" >&2; exit 1; }

require_option_value() {
  local option="$1"
  [ "$#" -ge 2 ] || die "$option requires a value."
  case "$2" in
    -*)
      if [ "$option" != '--year' ]; then
        die "$option requires a value."
      fi
      case "$2" in
        -[0-9]*) ;;
        *) die "$option requires a value." ;;
      esac
      ;;
  esac
}

require_integer_value() {
  local option="$1"
  local value="$2"
  local digits
  local negative=0
  local limit
  local LC_ALL=C

  invalid_year() {
    die "invalid $option '$value'. Use a numeric year (e.g. $(date +%Y))."
  }

  case "$value" in
    [0-9]*) digits="$value" ;;
    +[0-9]*) digits="${value#+}" ;;
    -[0-9]*) negative=1; digits="${value#-}" ;;
    *) invalid_year ;;
  esac
  case "$value" in
    *[!0-9+-]*) invalid_year ;;
  esac
  case "$digits" in
    ''|*[!0-9]*) invalid_year ;;
  esac

  while [ "${#digits}" -gt 1 ] && [ "${digits#0}" != "$digits" ]; do
    digits="${digits#0}"
  done

  if [ "$negative" -eq 1 ]; then
    limit=2147483648
  else
    limit=2147483647
  fi
  if [ "${#digits}" -gt "${#limit}" ] || {
    [ "${#digits}" -eq "${#limit}" ] && [[ "$digits" > "$limit" ]]
  }; then
    invalid_year
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project-name)
      require_option_value "$@"
      project_name="$2"
      shift 2
      ;;
    --author)
      require_option_value "$@"
      author="$2"
      shift 2
      ;;
    --author-email)
      require_option_value "$@"
      author_email="$2"
      shift 2
      ;;
    --github-owner)
      require_option_value "$@"
      github_owner="$2"
      shift 2
      ;;
    --description)
      require_option_value "$@"
      description="$2"
      shift 2
      ;;
    --year)
      require_option_value "$@"
      require_integer_value "--year" "$2"
      year="$2"
      shift 2
      ;;
    --keep-script)   keep_script=1; shift ;;
    -h|--help)       sed -n '2,20p' "$0"; exit 0 ;;
    *)               die "unknown argument: $1" ;;
  esac
done

[ -n "$project_name" ] || die "--project-name is required (e.g. --project-name Acme.Widgets)."

# Project / namespace / assembly / NuGet id: letters, digits, underscores;
# dot-separated segments allowed (e.g. Acme.Widgets). Mirrors init.ps1's regex
# ^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$.
# Reject a leading/trailing dot up front: `IFS='.' read` silently drops a
# trailing empty field, so `Acme.` would otherwise slip past the segment loop.
case "$project_name" in
  .*|*.) die "invalid --project-name '$project_name'. Use letters, digits, underscores; dot-separated segments allowed (e.g. Acme.Widgets)." ;;
esac
IFS='.' read -ra _segs <<< "$project_name"
for seg in "${_segs[@]}"; do
  case "$seg" in
    [A-Za-z_]*) ;;
    *) die "invalid --project-name '$project_name'. Use letters, digits, underscores; dot-separated segments allowed (e.g. Acme.Widgets)." ;;
  esac
  case "$seg" in
    *[!A-Za-z0-9_]*) die "invalid --project-name '$project_name'. Use letters, digits, underscores; dot-separated segments allowed (e.g. Acme.Widgets)." ;;
  esac
done

# Defaults (mirror init.ps1).
if [ -z "$author" ]; then
  author="$(git config user.name 2>/dev/null || true)"
  [ -n "$author" ] || author="Your Name"
fi
if [ -z "$author_email" ]; then
  author_email="$(git config user.email 2>/dev/null || true)"
  [ -n "$author_email" ] || author_email="you@example.com"
fi
[ -n "$github_owner" ] || github_owner="your-org"
[ -n "$description" ]  || description="TODO: project description"
[ -n "$year" ]         || year="$(date +%Y)"

metadata_value_has_control_character() {
  local value="$1"
  local char
  local i

  # Match each character instead of piping to grep, whose line-oriented input
  # treats an embedded newline as a separator rather than as matchable data.
  for ((i = 0; i < ${#value}; i++)); do
    char="${value:i:1}"
    case "$char" in
      [[:cntrl:]]) return 0 ;;
    esac
  done

  case "$value" in
    *$'\u2028'*|*$'\u2029'*) return 0 ;;
  esac
  return 1
}

validate_metadata() {
  local option="$1"
  local value="$2"
  if metadata_value_has_control_character "$value"; then
    die "invalid $option: metadata values must not contain control characters or line separators."
  fi
  case "$value" in
    *__ProjectName__*|*__Author__*|*__AuthorEmail__*|*__GitHubOwner__*|*__Description__*|*__Year__*)
      die "invalid $option: metadata values must not contain template tokens." ;;
  esac
}

validate_metadata '--author' "$author"
validate_metadata '--author-email' "$author_email"
validate_metadata '--github-owner' "$github_owner"
validate_metadata '--description' "$description"
if ! [[ "$github_owner" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]]; then
  die "invalid --github-owner '$github_owner'. Use letters, digits, and internal hyphens only."
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
self="$script_dir/$(basename "$0")"
sibling_ps1="$script_dir/init.ps1"

# Values written into XML files (e.g. the .fsproj <Authors>/<Description>) must be
# XML-escaped. Escape & first so the entities introduced below aren't re-escaped.
xml_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&apos;/g"
}

shell_escape() {
  local value="$1" escaped="" char i
  local backslash='\' dollar='$' backtick='`' quote='"'
  for ((i = 0; i < ${#value}; i++)); do
    char="${value:i:1}"
    case "$char" in
      "$backslash"|"$dollar"|"$backtick"|"$quote") escaped="${escaped}\\${char}" ;;
      *) escaped="${escaped}${char}" ;;
    esac
  done
  printf '%s' "$escaped"
}

python_escape() {
  local value="$1" escaped="" char i
  local backslash='\' quote='"'
  for ((i = 0; i < ${#value}; i++)); do
    char="${value:i:1}"
    case "$char" in
      "$backslash"|"$quote") escaped="${escaped}\\${char}" ;;
      *) escaped="${escaped}${char}" ;;
    esac
  done
  printf '%s' "$escaped"
}

json_escape() {
  local value="$1" escaped="" char i
  local backslash='\' quote='"'
  for ((i = 0; i < ${#value}; i++)); do
    char="${value:i:1}"
    case "$char" in
      "$backslash"|"$quote") escaped="${escaped}\\${char}" ;;
      *) escaped="${escaped}${char}" ;;
    esac
  done
  printf '%s' "$escaped"
}

rename_sources=()
rename_destinations=()
rename_targets=()
while IFS= read -r -d '' item; do
  case "$item" in
    */.git/*|*/.jj/*|*/bin/*|*/obj/*) continue ;;
  esac
  dir="$(dirname "$item")"
  base="$(basename "$item")"
  newbase="${base//__ProjectName__/$project_name}"
  if [ "$newbase" = "$base" ]; then
    continue
  fi

  target="$dir/$newbase"
  if [ -e "$target" ] || [ -L "$target" ]; then
    die "generated path collision: '$target' already exists (from '$item')."
  fi
  for planned_target in "${rename_targets[@]}"; do
    if [ "$planned_target" = "$target" ]; then
      die "generated path collision: multiple paths target '$target'."
    fi
  done
  rename_sources+=("$item")
  rename_destinations+=("$target")
  rename_targets+=("$target")
done < <(find "$repo_root" -depth -name '*__ProjectName__*' -print0)

project_x="$(xml_escape "$project_name")"
author_x="$(xml_escape "$author")"
email_x="$(xml_escape "$author_email")"
owner_x="$(xml_escape "$github_owner")"
desc_x="$(xml_escape "$description")"
year_x="$(xml_escape "$year")"
project_j="$(json_escape "$project_name")"
author_j="$(json_escape "$author")"
email_j="$(json_escape "$author_email")"
owner_j="$(json_escape "$github_owner")"
desc_j="$(json_escape "$description")"
year_j="$(json_escape "$year")"
project_sh="$(shell_escape "$project_name")"
author_sh="$(shell_escape "$author")"
email_sh="$(shell_escape "$author_email")"
owner_sh="$(shell_escape "$github_owner")"
desc_sh="$(shell_escape "$description")"
year_sh="$(shell_escape "$year")"
project_py="$(python_escape "$project_name")"
author_py="$(python_escape "$author")"
email_py="$(python_escape "$author_email")"
owner_py="$(python_escape "$github_owner")"
desc_py="$(python_escape "$description")"
year_py="$(python_escape "$year")"

echo "==> Initializing template as '$project_name'"

# 1) Replace tokens only in the template-owned text surface. User files are
#    deliberately absent from this list, even when they use a familiar text
#    extension or contain a placeholder-looking string.
known_text_paths=(
  '.claude/settings.json.template' '.config/dotnet-tools.json' '.editorconfig' '.gitattributes'
  '.github/CODEOWNERS' '.github/dependabot.yml' '.github/PULL_REQUEST_TEMPLATE.md'
  '.github/workflows/ci.yml' '.github/workflows/release.yml' '.gitignore' '.yamllint.yml'
  'AGENTS.md' 'CHANGELOG.md' 'CLAUDE.md' 'CONTRIBUTING.md' 'Directory.Build.props'
  'Directory.Packages.props' 'docs/AGENT-INIT-GUIDE.md' 'docs/linux-testing.md' 'global.json'
  'LICENSE' 'README.md' 'SECURITY.md' 'TEMPLATE.md' '__ProjectName__.sln.DotSettings'
  '__ProjectName__.slnx' 'cliff.toml' 'nuget.config' 'release-token-bypass.md'
  'scripts/check-env.ps1' 'scripts/check-env.sh' 'scripts/test-linux-regression.ps1'
  'scripts/test-linux.ps1' 'scripts/verify-nuget-package.py'
  'src/__ProjectName__/Greeter.fs' 'src/__ProjectName__/__ProjectName__.fsproj'
  'tests/__ProjectName__.Tests/GreeterTests.fs'
  'tests/__ProjectName__.Tests/__ProjectName__.Tests.fsproj'
  'tests/ci-tooling/constraints.txt' 'tests/ci-tooling/requirements.in'
  'tests/ci-tooling/test_sdk_alignment.py' 'tests/ci-tooling/test_yamllint_contract.py'
)
changed=0
for relative_path in "${known_text_paths[@]}"; do
  file="$repo_root/$relative_path"
  [ -f "$file" ] || continue
  case "$file" in
    "$self"|"$sibling_ps1") continue ;;
  esac
  # grep -I rejects NUL-containing files before command substitution can strip
  # their bytes. The explicit path list above also prevents user files from
  # reaching this read path at all.
  LC_ALL=C grep -Iq '' "$file" || continue
  p="$project_name"; a="$author"; ae="$author_email"; o="$github_owner"; d="$description"; y="$year"
  case "$file" in
    *.fsproj|*.props|*.targets|*.slnx|*.config)
      p="$project_x"; a="$author_x"; ae="$email_x"; o="$owner_x"; d="$desc_x"; y="$year_x" ;;
    *.json)
      p="$project_j"; a="$author_j"; ae="$email_j"; o="$owner_j"; d="$desc_j"; y="$year_j" ;;
    *.py)
      p="$project_py"; a="$author_py"; ae="$email_py"; o="$owner_py"; d="$desc_py"; y="$year_py" ;;
    *.sh|*.bash)
      p="$project_sh"; a="$author_sh"; ae="$email_sh"; o="$owner_sh"; d="$desc_sh"; y="$year_sh" ;;
    */.github/workflows/release.yml)
      a="$author_sh"; ae="$email_sh"; o="$owner_py" ;;
    *.yml|*.yaml)
      p="$project_j"; a="$author_j"; ae="$email_j"; o="$owner_j"; d="$desc_j"; y="$year_j" ;;
  esac
  # Preserve trailing newlines: append a sentinel before capture, strip it after.
  content="$(cat "$file"; printf x)"; content="${content%x}"
  orig="$content"
  new="$(TPL_SRC="$content" TPL_PROJECT="$p" TPL_AUTHOR="$a" \
    TPL_AUTHOR_EMAIL="$ae" TPL_OWNER="$o" TPL_DESC="$d" TPL_YEAR="$y" \
    awk '
      function replacement(tok) {
        if (tok == "__ProjectName__") return ENVIRON["TPL_PROJECT"]
        if (tok == "__Author__") return ENVIRON["TPL_AUTHOR"]
        if (tok == "__AuthorEmail__") return ENVIRON["TPL_AUTHOR_EMAIL"]
        if (tok == "__GitHubOwner__") return ENVIRON["TPL_OWNER"]
        if (tok == "__Description__") return ENVIRON["TPL_DESC"]
        return ENVIRON["TPL_YEAR"]
      }
      function repl(s, out, tok) {
        out = ""
        while (match(s, /__ProjectName__|__Author__|__AuthorEmail__|__GitHubOwner__|__Description__|__Year__/)) {
          tok = substr(s, RSTART, RLENGTH)
          out = out substr(s, 1, RSTART - 1) replacement(tok)
          s = substr(s, RSTART + RLENGTH)
        }
        return out s
      }
      BEGIN { printf "%s", repl(ENVIRON["TPL_SRC"]) }
    '; printf x)"
  new="${new%x}"
  content="$new"
  if [ "$content" != "$orig" ]; then
    printf '%s' "$content" > "$file"
    changed=$((changed + 1))
  fi
done
echo "    Updated contents in $changed file(s)."

# 2) Rename files and folders whose name contains the project-name token. -depth
#    processes children before parents so a renamed dir doesn't invalidate paths.
#    The complete plan was validated before content mutation.
for ((i = 0; i < ${#rename_sources[@]}; i++)); do
  item="${rename_sources[i]}"
  target="${rename_destinations[i]}"
  base="$(basename "$item")"
  newbase="$(basename "$target")"
  mv -- "$item" "$target"
  echo "    Renamed $base -> $newbase"
done

# 3) Activate the Claude Code shared settings. Shipped inert as a .template file
#    so the template repository itself does not auto-grant any permissions.
if [ -f "$repo_root/.claude/settings.json.template" ]; then
  mv -f "$repo_root/.claude/settings.json.template" "$repo_root/.claude/settings.json"
  echo "    Activated .claude/settings.json"
fi

# 4) Remove template-only files (the agent guide is template meta — pitfalls are
#    logged back to the *template's* copy, so the downstream repo drops it).
rm -f "$repo_root/TEMPLATE.md" "$repo_root/docs/AGENT-INIT-GUIDE.md"
# Drop docs/ if it's now empty (it may still hold linux-testing.md, in which case
# rmdir fails harmlessly and the directory is kept).
rmdir "$repo_root/docs" 2>/dev/null || true

echo ""
echo "Done. Next steps:"
echo "  1. dotnet tool restore           # restores Fantomas (the F# formatter)"
echo "  2. dotnet build $project_name.slnx"
echo "  3. dotnet test  $project_name.slnx"
echo "  4. Review LICENSE (author/year) and the .fsproj package metadata."
echo "  5. NuGet publishing: add the NUGET_API_KEY repo secret, or delete"
echo "     .github/workflows/release.yml and the packaging properties in the .fsproj."
echo "  6. Commit the initialized project."

# 5) Remove both initializers unless asked to keep them.
if [ "$keep_script" -ne 1 ]; then
  rm -f "$sibling_ps1"
  rm -f "$self"
fi
