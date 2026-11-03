#!/usr/bin/env bash
# Test www_site (#44) in a throwaway LXD system container on the VM:
#   launch -> droplet-infra's host layer -> refusal without a certificate -> run ->
#   run again (changed=0) -> check mode (changed=0) -> verify, including a page
#   through landing-deploy -> drift is seen, then repaired -> delete
#
#   infra/test.sh            # keeps nothing
#   KEEP=1 infra/test.sh     # leaves the container up to poke at
#
# It creates and deletes ONLY containers named www-*. Containers, never --vm: the VM
# has no /dev/kvm. LXD must be initialised first (infra/README.md).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
ansible_dir=$here/ansible
venv=$here/.venv
role_files=$ansible_dir/roles/www_site/files
name="www-site-$(date +%s)"

die() { echo "infra/test.sh: $*" >&2; exit 1; }
step() { printf '\n== %s\n' "$*"; }

delete_container() {
  [[ $1 == www-* ]] || die "refusing to delete '$1': not a www- container"
  lxc delete --force "$1" >/dev/null 2>&1 || true
}

command -v lxc >/dev/null || die "lxc not found; LXD is not installed"
lxc storage show default >/dev/null 2>&1 || die "LXD is not initialised; see infra/README.md"

# --- the control node: pinned ansible-core, collections and host layer --------
step "control node"
if [[ ! -x $venv/bin/ansible-playbook ]] || ! cmp -s "$here/requirements-infra.txt" "$venv/.requirements"; then
  # --clear: over an old venv, a package already installed would satisfy pip check
  # and hide a dependency this list has lost.
  python3 -m venv --clear "$venv"
  "$venv/bin/pip" install -q --no-deps -r "$here/requirements-infra.txt"
  "$venv/bin/pip" check || die "requirements-infra.txt is missing a dependency; pin it there"
  cp "$here/requirements-infra.txt" "$venv/.requirements"
fi
export PATH="$venv/bin:$PATH"
"$here/fetch_host_role.sh"
cd "$ansible_dir"
ansible-galaxy collection install -r requirements.yml -p ./collections >/dev/null
ansible --version | head -1

# --- nothing private is committable ------------------------------------------
step "the real inventory is gitignored"
git -C "$here/.." check-ignore -q infra/ansible/inventory.yml \
  || die "infra/ansible/inventory.yml is NOT gitignored; the real inventory would be committable"
echo "ok: infra/ansible/inventory.yml is ignored"

# --- launch ------------------------------------------------------------------
step "launch $name"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"; [[ ${KEEP:-} == 1 ]] || delete_container "$name"' EXIT
# </dev/null: off a terminal, lxc launch reads its config from stdin, so an open
# pipe or socket hangs it forever. The timeout stays so any other hang says so.
timeout 300 lxc launch -q ubuntu:24.04 "$name" -c security.nesting=true </dev/null \
  || die "lxc launch failed or took over 5 minutes (try: lxc image list; lxc launch by hand)"
lxc exec "$name" -- cloud-init status --wait >/dev/null || true

ct() { lxc exec "$name" -- "$@"; }

# Docker on the VM sets the FORWARD policy to DROP, which silently blackholes LXD's
# bridge. Fail here, naming the fix, rather than in apt ten minutes later.
ct timeout 15 curl -fsS -o /dev/null https://download.docker.com/ \
  || die "the container has no internet. Docker's FORWARD DROP is blocking lxdbr0; see infra/README.md"

# Nothing here may reach Let's Encrypt; the certificate is self-signed.
ct sh -c 'echo "127.0.0.1 acme-v02.api.letsencrypt.org" >> /etc/hosts'

cat > "$tmp/inventory.yml" <<INVENTORY
droplet:
  hosts:
    $name:
      ansible_connection: community.general.lxd
INVENTORY
play() { ansible-playbook -i "$tmp/inventory.yml" "$@"; }
recap_ok() { grep -qE "^$name +: ok=[0-9]+ +changed=0 +unreachable=0 +failed=0" "$1"; }

# Run the playbook expecting a refusal that names $2. $1 labels the log.
refused() {
  local log=$tmp/$1.log
  if play site.yml >"$log" 2>&1; then cat "$log"; die "$1: the run passed"; fi
  grep -qF "$2" "$log" || { cat "$log"; die "$1: the failure doesn't name $2"; }
  echo "ok: refused, named $2"
}

response_headers() { ct curl -skI --resolve "$1:443:127.0.0.1" "https://$1/"; }

# --- the host layer: droplet-infra's host.yml, at the pin ----------------------
step "droplet-infra's host layer"
play vendor/droplet-infra/infra/ansible/host.yml >"$tmp/host.log" || { cat "$tmp/host.log"; die "the host layer failed"; }
tail -3 "$tmp/host.log"

# --- refusal: the certificate --------------------------------------------------
step "no certificate: the run must fail and name it"
refused no-cert 'live/seandesmet.com/fullchain.pem is missing'
ct test ! -e /etc/nginx/sites-enabled/seandesmet.com || die "the site was enabled before its certificate existed"
ct sh -c '
  set -e
  d=/etc/letsencrypt/live/seandesmet.com && mkdir -p "$d"
  openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj /CN=seandesmet.com \
    -keyout "$d/privkey.pem" -out "$d/fullchain.pem" 2>/dev/null
  cp "$(find /usr/lib/python3/dist-packages -name options-ssl-nginx.conf | head -1)" /etc/letsencrypt/
  cp "$(find /usr/lib/python3/dist-packages -name ssl-dhparams.pem | head -1)" /etc/letsencrypt/'

# --- first full run, then nothing to do ---------------------------------------
step "first run"
play site.yml

step "second run (must report changed=0)"
play site.yml | tee "$tmp/second.log"
recap_ok "$tmp/second.log" || die "the second run changed something or failed; see the recap above"

step "check mode (as on production; must report changed=0)"
play site.yml --check --diff | tee "$tmp/check.log"
recap_ok "$tmp/check.log" || die "check mode reports a change on a host the role just built"

# --- verify --------------------------------------------------------------------
step "verify"
ct nginx -t
[[ $(ct readlink /etc/nginx/sites-enabled/seandesmet.com) == /etc/nginx/sites-available/seandesmet.com ]] \
  || die "the site is not enabled"
same_as_role() { cmp -s <(ct cat "$1") "$role_files/$2" || die "$1 differs from the role's $2"; }
same_as_role /etc/nginx/sites-available/seandesmet.com seandesmet.com
same_as_role /etc/nginx/snippets/seandesmet-security-headers.conf seandesmet-security-headers.conf
same_as_role /usr/local/bin/landing-deploy landing-deploy
[[ $(ct stat -c '%a %U:%G' /etc/nginx/sites-available/seandesmet.com) == '644 root:root' ]] || die "the site file is not 644 root:root"
[[ $(ct stat -c '%a %U:%G' /etc/nginx/snippets/seandesmet-security-headers.conf) == '644 root:root' ]] || die "the snippet is not 644 root:root"
[[ $(ct stat -c '%a %U:%G' /usr/local/bin/landing-deploy) == '755 root:root' ]] || die "landing-deploy is not 755 root:root"
[[ $(ct stat -c '%a %U:%G' /var/www/seandesmet.com) == '755 deploy:deploy' ]] || die "the web root is not 755 deploy:deploy"
ct test ! -e /var/www/seandesmet.com/index.html || die "the role wrote the page; landing-deploy owns it"
ct test ! -e /etc/letsencrypt/accounts || die "an ACME account exists; something asked Let's Encrypt"

# landing-deploy as the deploy key runs it: only index.html lands, wherever else a
# tarball aims, and a tarball without one is refused and installs nothing.
ct sh -c 'cd "$(mktemp -d)" && touch other.css && tar -czf - other.css | runuser -u deploy -- /usr/local/bin/landing-deploy' \
  && die "landing-deploy accepted a tarball with no index.html"
ct test ! -e /var/www/seandesmet.com/index.html || die "landing-deploy installed something from a tarball with no index.html"
ct sh -c 'cd "$(mktemp -d)" && echo www-page > index.html && touch other.css && tar -czf - index.html other.css | runuser -u deploy -- /usr/local/bin/landing-deploy'
ct test ! -e /var/www/seandesmet.com/other.css || die "landing-deploy installed more than index.html"
[[ $(ct stat -c '%a %U:%G' /var/www/seandesmet.com/index.html) == '644 deploy:deploy' ]] || die "the page is not 644 deploy:deploy"

for host in seandesmet.com www.seandesmet.com; do
  body=$(ct curl -sk --resolve "$host:443:127.0.0.1" "https://$host/")
  [[ $body == www-page ]] || die "https://$host/ did not serve the web root (got: $body)"
  headers=$(response_headers "$host" | tr -d '\r')
  for want in \
    "Strict-Transport-Security: max-age=31536000" \
    "Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'" \
    "X-Content-Type-Options: nosniff" \
    "Referrer-Policy: strict-origin-when-cross-origin" \
    "Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=(), usb=()" \
    "X-Frame-Options: DENY" \
    "Cross-Origin-Opener-Policy: same-origin" \
    "Content-Type: text/html; charset=utf-8" \
    "Server: nginx"; do
    grep -qixF "$want" <<<"$headers" || die "https://$host/ lacks exactly: $want"
  done
done
for host in seandesmet.com www.seandesmet.com; do
  redirect=$(ct curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --resolve "$host:80:127.0.0.1" "http://$host/x")
  [[ $redirect == "301 https://$host/x" ]] || die "http://$host/ does not redirect to HTTPS (got: $redirect)"
done
echo "ok: enabled, nginx -t passes, a page through landing-deploy serves with production's headers"

# --- drift: production's check is only worth reading if it can fail ------------
drift_checked() {
  play site.yml --check --diff | tee "$tmp/drift.log"
  if recap_ok "$tmp/drift.log"; then die "check mode reported changed=0 with $1 different from the role's"; fi
  grep -qE "^$name +: ok=[0-9]+ +changed=[1-9][0-9]* +unreachable=0 +failed=0" "$tmp/drift.log" \
    || die "check mode failed instead of reporting the drift in $1"
}

step "drift in all three files: check mode must report it and change nothing"
csp() { grep -i '^content-security-policy' <<<"$(response_headers seandesmet.com)" || true; }
# A reload returns before the new workers answer, so an immediate request can still
# reach an old one. Wait for the state this expects, and fail if it never comes.
csp_becomes() {
  local i
  for i in {1..20}; do
    if [[ $1 == absent && -z $(csp) || $1 == present && -n $(csp) ]]; then return 0; fi
    sleep 0.5
  done
  return 1
}
ct sh -c "sed -i '/Content-Security-Policy/d' /etc/nginx/snippets/seandesmet-security-headers.conf \
  && echo '# drift' >> /etc/nginx/sites-available/seandesmet.com \
  && echo '# drift' >> /usr/local/bin/landing-deploy \
  && systemctl reload nginx"
csp_becomes absent || die "the drift did not remove the CSP, so this step proves nothing"
drifted=$(ct sha256sum /etc/nginx/snippets/seandesmet-security-headers.conf /etc/nginx/sites-available/seandesmet.com /usr/local/bin/landing-deploy)
drift_checked "all three files"
[[ $(ct sha256sum /etc/nginx/snippets/seandesmet-security-headers.conf /etc/nginx/sites-available/seandesmet.com /usr/local/bin/landing-deploy) == "$drifted" ]] \
  || die "check mode changed a file"
sleep 2
[[ -z $(csp) ]] || die "check mode reloaded nginx"

step "drift: a real run must repair it and reload nginx"
play site.yml >"$tmp/repair.log" || { cat "$tmp/repair.log"; die "the repair run failed"; }
same_as_role /etc/nginx/sites-available/seandesmet.com seandesmet.com
same_as_role /etc/nginx/snippets/seandesmet-security-headers.conf seandesmet-security-headers.conf
same_as_role /usr/local/bin/landing-deploy landing-deploy
csp_becomes present || die "the snippet was repaired but nginx was not reloaded"
[[ $(ct cat /var/www/seandesmet.com/index.html) == www-page ]] || die "the repair run touched the page"
echo "ok: repaired, reloaded, and the page was left alone"

echo
echo "PASS: $name: refused without a certificate, built, second run and check mode changed=0, drift seen and repaired"
if [[ ${KEEP:-} == 1 ]]; then
  echo "KEEP=1: left $name running; delete it with: lxc delete --force $name"
fi
