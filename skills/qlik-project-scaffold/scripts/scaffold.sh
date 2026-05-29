#!/usr/bin/env bash
set -euo pipefail

project_root="${1:-.}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
assets_dir="$(cd "$script_dir/../assets" && pwd)"

mkdir -p "$project_root"
project_root="$(cd "$project_root" && pwd)"

dirs=(data-sources scripts qvds documentation tests)

for d in "${dirs[@]}"; do
    target_dir="$project_root/$d"
    if [ ! -d "$target_dir" ]; then
        mkdir -p "$target_dir"
        echo "Created: $target_dir"
    else
        echo "Exists:  $target_dir"
    fi

    target_readme="$target_dir/README.md"
    source_readme="$assets_dir/$d-README.md"
    if [ ! -f "$target_readme" ]; then
        if [ -f "$source_readme" ]; then
            cp "$source_readme" "$target_readme"
            echo "Wrote:   $target_readme"
        else
            echo "Warning: template missing: $source_readme (skipped README)" >&2
        fi
    else
        echo "Kept:    $target_readme (existing file preserved)"
    fi
done

echo
echo "Scaffold complete in: $project_root"
