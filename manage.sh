#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POSTS_DIR="$ROOT_DIR/content/posts"
ATTACHMENTS_DIR="$ROOT_DIR/static/attachments"
DEFAULT_BIND="${HUGO_BIND:-10.8.0.1}"
DEFAULT_PORT="${HUGO_PORT:-1313}"

usage() {
  cat <<'EOF'
Usage:
  ./bin/manage run [extra hugo server args...]
  ./bin/manage new <slug>
  ./bin/manage edit <slug>
  ./bin/manage rename <old-slug> <new-slug>
  ./bin/manage mv <old-slug> <new-slug>
  ./bin/manage list [posts|attachments|all]
  ./bin/manage copy <source-file> [target-name]
  ./bin/manage rm <slug>
  ./bin/manage rm post <slug>
  ./bin/manage rm attachment <name>
  ./bin/manage remove ...
  ./bin/manage completion bash
  ./bin/manage setup-shell

Examples:
  ./bin/manage run
  ./bin/manage new my-post
  ./bin/manage edit my-post
  ./bin/manage rename old-post new-post
  ./bin/manage list
  ./bin/manage copy ~/Downloads/image.png
  ./bin/manage rm my-post
  ./bin/manage rm attachment image.png
  ./bin/manage setup-shell
  source <(./bin/manage completion bash)
EOF
}

print_completion() {
  cat <<'EOF'
_hugo_manage_completions() {
  local cur prev words cword
  words=("${COMP_WORDS[@]}")
  cword="$COMP_CWORD"
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev=""
  if (( COMP_CWORD > 0 )); then
    prev="${COMP_WORDS[COMP_CWORD-1]}"
  fi

  local commands="run new edit rename mv list copy rm remove completion setup-shell help"
  local list_targets="posts attachments all"
  local remove_targets="post attachment"
  local posts attachments

  if [[ -d /opt/hugo/content/posts ]]; then
    posts="$(cd /opt/hugo/content/posts && printf '%s\n' *.md 2>/dev/null | sed 's/\.md$//')"
  fi

  if [[ -d /opt/hugo/static/attachments ]]; then
    attachments="$(cd /opt/hugo/static/attachments && find . -maxdepth 1 -type f ! -name '.gitkeep' -printf '%P\n' 2>/dev/null)"
  fi

  case "${words[1]:-}" in
    edit)
      COMPREPLY=( $(compgen -W "$posts" -- "$cur") )
      return
      ;;
    rename|mv)
      if [[ $cword -eq 2 ]]; then
        COMPREPLY=( $(compgen -W "$posts" -- "$cur") )
      fi
      return
      ;;
    list)
      COMPREPLY=( $(compgen -W "$list_targets" -- "$cur") )
      return
      ;;
    rm|remove)
      if [[ $cword -eq 2 ]]; then
        COMPREPLY=( $(compgen -W "$remove_targets $posts" -- "$cur") )
        return
      fi
      if [[ ${words[2]:-} == "post" ]]; then
        COMPREPLY=( $(compgen -W "$posts" -- "$cur") )
        return
      fi
      if [[ ${words[2]:-} == "attachment" ]]; then
        COMPREPLY=( $(compgen -W "$attachments" -- "$cur") )
        return
      fi
      ;;
    completion)
      COMPREPLY=( $(compgen -W "bash" -- "$cur") )
      return
      ;;
  esac

  if [[ $cword -eq 1 ]]; then
    COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
    return
  fi

  if [[ ${words[1]:-} == "copy" ]]; then
    COMPREPLY=( $(compgen -f -- "$cur") )
  fi
}

complete -F _hugo_manage_completions ./bin/manage
complete -F _hugo_manage_completions manage
complete -F _hugo_manage_completions ./bin/hugo-manage
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

normalize_slug() {
  local slug="$1"
  slug="${slug##*/}"
  slug="${slug%.md}"
  if [[ -z "$slug" ]]; then
    echo "Slug cannot be empty." >&2
    exit 1
  fi
  printf '%s\n' "$slug"
}

post_path() {
  local slug
  slug="$(normalize_slug "$1")"
  printf '%s/%s.md\n' "$POSTS_DIR" "$slug"
}

list_posts() {
  find "$POSTS_DIR" -maxdepth 1 -type f -name '*.md' -printf '%f\n' | sed 's/\.md$//' | sort
}

list_attachments() {
  find "$ATTACHMENTS_DIR" -maxdepth 1 -type f ! -name '.gitkeep' -printf '%f\n' | sort
}

open_editor() {
  local target="$1"
  local editor="${EDITOR:-}"

  if [[ -n "$editor" ]] && command -v "$editor" >/dev/null 2>&1; then
    "$editor" "$target"
    return
  fi

  if command -v nvim >/dev/null 2>&1; then
    nvim "$target"
    return
  fi

  if command -v nano >/dev/null 2>&1; then
    nano "$target"
    return
  fi

  if command -v vim >/dev/null 2>&1; then
    vim "$target"
    return
  fi

  if command -v vi >/dev/null 2>&1; then
    vi "$target"
    return
  fi

  echo "No editor found. Set \$EDITOR or install nvim/nano/vim." >&2
  exit 1
}

cmd_run() {
  require_command hugo
  cd "$ROOT_DIR"
  hugo server -D --bind "$DEFAULT_BIND" --baseURL "http://$DEFAULT_BIND:$DEFAULT_PORT/" "$@"
}

cmd_new() {
  require_command hugo
  if [[ $# -ne 1 ]]; then
    usage
    exit 1
  fi

  local slug target
  slug="$(normalize_slug "$1")"
  target="posts/$slug.md"

  cd "$ROOT_DIR"
  hugo new "$target"
  echo "Created: $POSTS_DIR/$slug.md"
}

cmd_edit() {
  if [[ $# -ne 1 ]]; then
    usage
    exit 1
  fi

  local target
  target="$(post_path "$1")"
  if [[ ! -f "$target" ]]; then
    echo "Post not found: $target" >&2
    exit 1
  fi

  open_editor "$target"
}

cmd_rename() {
  if [[ $# -ne 2 ]]; then
    usage
    exit 1
  fi

  local old_target new_target
  old_target="$(post_path "$1")"
  new_target="$(post_path "$2")"

  if [[ ! -f "$old_target" ]]; then
    echo "Post not found: $old_target" >&2
    exit 1
  fi

  if [[ -e "$new_target" ]]; then
    echo "Target already exists: $new_target" >&2
    exit 1
  fi

  mv "$old_target" "$new_target"
  echo "Renamed post: $old_target -> $new_target"
}

cmd_list() {
  local kind="${1:-all}"

  case "$kind" in
    posts)
      list_posts
      ;;
    attachments)
      list_attachments
      ;;
    all)
      echo "[posts]"
      list_posts
      echo
      echo "[attachments]"
      list_attachments
      ;;
    *)
      echo "List target must be 'posts', 'attachments', or 'all'." >&2
      exit 1
      ;;
  esac
}

cmd_copy() {
  if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage
    exit 1
  fi

  local source_file target_name
  source_file="$1"
  if [[ ! -f "$source_file" ]]; then
    echo "Source file not found: $source_file" >&2
    exit 1
  fi

  mkdir -p "$ATTACHMENTS_DIR"
  target_name="${2:-$(basename "$source_file")}"
  cp "$source_file" "$ATTACHMENTS_DIR/$target_name"
  echo "Copied: $ATTACHMENTS_DIR/$target_name"
  echo "URL: /attachments/$target_name"
  echo "Markdown: [$(basename "$target_name")](/attachments/$target_name)"
}

cmd_remove() {
  if [[ $# -eq 1 ]]; then
    set -- post "$1"
  fi

  if [[ $# -ne 2 ]]; then
    usage
    exit 1
  fi

  case "$1" in
    post)
      local target
      target="$(post_path "$2")"
      if [[ ! -f "$target" ]]; then
        echo "Post not found: $target" >&2
        exit 1
      fi
      rm "$target"
      echo "Removed post: $target"
      ;;
    attachment)
      local target
      target="$ATTACHMENTS_DIR/$2"
      if [[ ! -f "$target" ]]; then
        echo "Attachment not found: $target" >&2
        exit 1
      fi
      rm "$target"
      echo "Removed attachment: $target"
      ;;
    *)
      echo "Remove target must be 'post' or 'attachment'." >&2
      exit 1
      ;;
  esac
}

cmd_completion() {
  if [[ $# -ne 1 || "$1" != "bash" ]]; then
    echo "Usage: ./bin/manage completion bash" >&2
    exit 1
  fi

  print_completion
}

cmd_setup_shell() {
  require_command bash

  local rcfile
  rcfile="$(mktemp)"

  cat >"$rcfile" <<EOF
if [[ -f ~/.bashrc ]]; then
  source ~/.bashrc
fi
source <("$ROOT_DIR/bin/manage" completion bash)
alias manage="$ROOT_DIR/bin/manage"
cd "$ROOT_DIR"
echo "Temporary manage shell loaded for $ROOT_DIR"
echo "Available: manage run | manage new <slug> | manage edit <slug> | manage rename <old> <new> | manage list"
EOF

  bash --rcfile "$rcfile" -i
  rm -f "$rcfile"
}

main() {
  mkdir -p "$POSTS_DIR" "$ATTACHMENTS_DIR"

  if [[ $# -lt 1 ]]; then
    usage
    exit 1
  fi

  local command="$1"
  shift

  case "$command" in
    run)
      cmd_run "$@"
      ;;
    new)
      cmd_new "$@"
      ;;
    edit)
      cmd_edit "$@"
      ;;
    rename|mv)
      cmd_rename "$@"
      ;;
    list)
      cmd_list "$@"
      ;;
    copy)
      cmd_copy "$@"
      ;;
    rm|remove)
      cmd_remove "$@"
      ;;
    completion)
      cmd_completion "$@"
      ;;
    setup-shell)
      cmd_setup_shell "$@"
      ;;
    help|-h|--help)
      usage
      ;;
    *)
      echo "Unknown command: $command" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"