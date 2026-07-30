#!/usr/bin/env bash
# Migrate plugins from lazy.nvim's lazy-lock.json into nvpm (pinned commits).
#
# Usage:
#   ./migrate-from-lazy.nvim-package-manager.sh [--dry-run] [--lockfile PATH] [--lazy-root PATH]
#
# Resolves each lock entry to provider:owner/repo@commit via the plugin's git remote
# under the lazy root (lockfile only stores name + commit).
set -euo pipefail

DRY_RUN=0
LOCKFILE=""
LAZY_ROOT=""

usage() {
  cat <<'EOF'
Migrate lazy.nvim lockfile plugins to nvpm.

Usage:
  migrate-from-lazy.nvim-package-manager.sh [options]

Options:
  --dry-run          Print the nvpm add command without running it
  --lockfile PATH    Path to lazy-lock.json (default: stdpath("config")/lazy-lock.json)
  --lazy-root PATH   Lazy plugin install root (default: stdpath("data")/lazy)
  -h, --help         Show this help

Requires: nvim, nvpm, git, and either python3 or jq

Note: lazy.nvim itself is always skipped.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --lockfile)
      LOCKFILE="${2:-}"
      [[ -n "$LOCKFILE" ]] || { echo "error: --lockfile needs a path" >&2; exit 2; }
      shift 2
      ;;
    --lazy-root)
      LAZY_ROOT="${2:-}"
      [[ -n "$LAZY_ROOT" ]] || { echo "error: --lazy-root needs a path" >&2; exit 2; }
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: required command not found: $1" >&2
    exit 1
  }
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

need_cmd nvim
need_cmd nvpm
need_cmd git

if have_cmd python3; then
  LOCK_PARSER=python3
elif have_cmd jq; then
  LOCK_PARSER=jq
else
  echo "error: need python3 or jq to parse lazy-lock.json" >&2
  echo "hint: install one of them, e.g. 'python3' or 'jq', then re-run this script" >&2
  exit 1
fi

nvim_stdpath() {
  # -u NONE: no user config; still respects XDG / NVIM_APPNAME for stdpath.
  nvim --headless -u NONE \
    -c "lua io.stdout:write(vim.fn.stdpath([[$1]]))" \
    -c "qa!" 2>/dev/null
}

if [[ -z "$LOCKFILE" ]]; then
  LOCKFILE="$(nvim_stdpath config)/lazy-lock.json"
fi
if [[ -z "$LAZY_ROOT" ]]; then
  LAZY_ROOT="$(nvim_stdpath data)/lazy"
fi

if [[ ! -f "$LOCKFILE" ]]; then
  echo "error: lazy-lock.json not found at: $LOCKFILE" >&2
  echo "hint: pass --lockfile PATH, or ensure lazy.nvim wrote the lockfile" >&2
  exit 1
fi

if [[ ! -d "$LAZY_ROOT" ]]; then
  echo "error: lazy plugin root not found at: $LAZY_ROOT" >&2
  echo "hint: pass --lazy-root PATH (plugins must be installed so remotes can be read)" >&2
  exit 1
fi

echo "lockfile:  $LOCKFILE"
echo "lazy root: $LAZY_ROOT"
echo "parser:    $LOCK_PARSER"

# Emit lines: name<TAB>commit<TAB>url  (always skips lazy.nvim)
parse_lockfile() {
  if [[ "$LOCK_PARSER" == "python3" ]]; then
    LOCKFILE="$LOCKFILE" python3 - <<'PY'
import json, os, sys

path = os.environ["LOCKFILE"]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
if not isinstance(data, dict):
    sys.stderr.write("error: lazy-lock.json must be a JSON object\n")
    sys.exit(1)

for name in sorted(data.keys()):
    if name == "lazy.nvim":
        continue
    entry = data[name]
    if not isinstance(entry, dict):
        continue
    commit = entry.get("commit")
    if not commit:
        sys.stderr.write(f"warn: skipping {name}: missing commit\n")
        continue
    # Optional community/extended field
    url = entry.get("url") or ""
    print(f"{name}\t{commit}\t{url}")
PY
    return
  fi

  # jq fallback
  if ! jq -e 'type == "object"' "$LOCKFILE" >/dev/null 2>&1; then
    echo "error: lazy-lock.json must be a JSON object" >&2
    exit 1
  fi
  # to_entries → sorted by key; skip lazy.nvim; require .value.commit
  jq -r '
    to_entries
    | sort_by(.key)
    | .[]
    | select(.key != "lazy.nvim")
    | select((.value | type) == "object")
    | select(.value.commit != null and .value.commit != "")
    | [.key, .value.commit, (.value.url // "")]
    | @tsv
  ' "$LOCKFILE"
}

mapfile -t ENTRIES < <(parse_lockfile)

if [[ ${#ENTRIES[@]} -eq 0 ]]; then
  echo "error: no migratable plugins found in lockfile" >&2
  exit 1
fi

# Map git remote URL → nvpm package id prefix (provider:owner/repo)
url_to_source_id() {
  local url="$1"
  # trim whitespace, then strip trailing .git / slash
  url="$(printf '%s' "$url" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  url="${url%.git}"
  url="${url%/}"

  local host="" path=""

  if [[ "$url" =~ ^git@([^:]+):(.+)$ ]]; then
    host="${BASH_REMATCH[1]}"
    path="${BASH_REMATCH[2]}"
  elif [[ "$url" =~ ^ssh://([^@]+@)?([^/]+)/(.+)$ ]]; then
    host="${BASH_REMATCH[2]}"
    path="${BASH_REMATCH[3]}"
  elif [[ "$url" =~ ^https?://([^/]+)/(.+)$ ]]; then
    host="${BASH_REMATCH[1]}"
    path="${BASH_REMATCH[2]}"
  elif [[ "$url" =~ ^git://([^/]+)/(.+)$ ]]; then
    host="${BASH_REMATCH[1]}"
    path="${BASH_REMATCH[2]}"
  else
    return 1
  fi

  # drop userinfo from host if present (user@host)
  host="${host##*@}"
  path="${path#/}"
  path="${path%.git}"

  local provider=""
  case "$host" in
    github.com|www.github.com) provider="github" ;;
    gitlab.com|www.gitlab.com) provider="gitlab" ;;
    codeberg.org|www.codeberg.org) provider="codeberg" ;;
    forgejo.org|www.forgejo.org) provider="forgejo" ;;
    *)
      return 2
      ;;
  esac

  printf '%s:%s' "$provider" "$path"
}

PKG_IDS=()
SKIPPED=0
RESOLVED=0

for line in "${ENTRIES[@]}"; do
  IFS=$'\t' read -r name commit url <<<"$line"
  source_id=""

  if [[ -n "$url" ]]; then
    if source_id="$(url_to_source_id "$url")"; then
      :
    else
      echo "warn: $name: lock url not a supported host: $url" >&2
      source_id=""
    fi
  fi

  if [[ -z "$source_id" ]]; then
    plugin_dir="$LAZY_ROOT/$name"
    if [[ ! -d "$plugin_dir" ]]; then
      echo "warn: skip $name@$commit - not installed under lazy root (need remote to map owner/repo)" >&2
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
    if ! remote_url="$(git -C "$plugin_dir" remote get-url origin 2>/dev/null)"; then
      echo "warn: skip $name@$commit - no git remote 'origin' in $plugin_dir" >&2
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
    if ! source_id="$(url_to_source_id "$remote_url")"; then
      rc=$?
      if [[ $rc -eq 2 ]]; then
        echo "warn: skip $name@$commit - unsupported git host in remote: $remote_url" >&2
        echo "       supported: github.com, gitlab.com, codeberg.org, forgejo.org" >&2
      else
        echo "warn: skip $name@$commit - could not parse remote: $remote_url" >&2
      fi
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
  fi

  pkg_id="${source_id}@${commit}"
  PKG_IDS+=("$pkg_id")
  RESOLVED=$((RESOLVED + 1))
  echo "  + $name → $pkg_id"
done

if [[ ${#PKG_IDS[@]} -eq 0 ]]; then
  echo "error: nothing to install ($SKIPPED skipped)" >&2
  exit 1
fi

echo
echo "resolved: $RESOLVED  skipped: $SKIPPED"

CMD=(nvpm add --force --plugin neovim "${PKG_IDS[@]}")

echo
printf 'command:'
printf ' %q' "${CMD[@]}"
echo

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "dry-run: not executing"
  exit 0
fi

echo
exec "${CMD[@]}"
