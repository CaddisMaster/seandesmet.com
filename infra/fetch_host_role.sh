#!/usr/bin/env bash
# Fetch droplet-infra at the commit infra/host-role.pin names, into
# infra/ansible/vendor/droplet-infra (gitignored). Only infra/test.sh uses it: this
# repo's playbook never runs the host layer, on production or anywhere else.
# Fetching by SHA means the pin is the only thing that decides which role runs.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=/dev/null
. "$here/host-role.pin"
[[ $sha =~ ^[0-9a-f]{40}$ ]] || { echo "fetch_host_role.sh: host-role.pin's sha is not a full commit SHA" >&2; exit 1; }

dest=$here/ansible/vendor/droplet-infra
if [[ $(git -C "$dest" rev-parse HEAD 2>/dev/null) != "$sha" ]]; then
  rm -rf "$dest" && mkdir -p "$dest"
  git -C "$dest" init -q
  git -C "$dest" fetch -q --depth 1 "$repo" "$sha"
  git -C "$dest" checkout -q FETCH_HEAD
fi
[[ $(git -C "$dest" rev-parse HEAD) == "$sha" ]] || { echo "fetch_host_role.sh: vendor checkout is not at $sha" >&2; exit 1; }
[[ -f $dest/infra/ansible/host.yml ]] || { echo "fetch_host_role.sh: no host.yml at $sha" >&2; exit 1; }
echo "host layer: droplet-infra at ${sha:0:7}"
