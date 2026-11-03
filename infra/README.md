# infra/: seandesmet.com's part of the Droplet as code

The Droplet is shared with Budget Buddy and Orbit Ops. The host layer under this is
[`droplet-infra`](https://github.com/CaddisMaster/droplet-infra)'s. **Nothing runs this playbook
automatically**: `deploy.yml` doesn't touch `infra/`, and a merge here deploys nothing.

| Path | What it is |
|---|---|
| `ansible/site.yml` | The playbook: `www_site` and nothing else, so it can't change the host or another tenant's site |
| `ansible/roles/www_site/` | The site file and its enabled link, the web root, the headers snippet, and `landing-deploy` |
| `test.sh` | The LXD test, on top of `droplet-infra`'s `host.yml` |
| `host-role.pin`, `fetch_host_role.sh` | `droplet-infra` by commit SHA, for the test only. Bump the pin in its own PR, after reading the diff |
| `requirements-infra.txt`, `ansible/requirements.yml` | The control node's exact pins, the same versions as `droplet-infra`'s at the pin |

**What the role doesn't own:**

- **The page:** `deploy.yml` sends it through `landing-deploy`
- **The deploy key's `authorized_keys` line:** `droplet-infra`'s inventory declares it. The line
  this repo's key needs is in `SETUP.md` §4
- **The certificate:** Certbot's, with its own lineage. The role only checks that it exists and
  refuses otherwise (`README.md` §Certificates)

⚠️ **The files in `roles/www_site/files/` are production's, byte for byte** (compared on the Droplet
on 2026-11-03, #44). `seandesmet-security-headers.conf` is a contract with `index.html`, and
`landing-deploy` is the deploy key's security boundary. A change to either reaches production
only through a run that Sean decides on, so check mode will report it until then.

## The test

⚠️ **Warn Sean before a run.** The VM is on Sean's Mac and a run is about 5 minutes of load. Other
repos' sessions may want LXD too, so check `lxc list` first.

```bash
infra/test.sh           # host layer → refusal → run → run again → check mode → verify → drift → delete
KEEP=1 infra/test.sh    # leave the container up to poke at
```

It creates and deletes **only** containers named `www-*`. It uses stand-ins for the certificate
and blocks Let's Encrypt, so TLS issuance isn't exercised. It checks that:

1. With no certificate, the run fails naming `fullchain.pem` and the site isn't enabled
2. A full run works, then a second run and a `--check --diff` run both report `changed=0`
3. `nginx -t` passes, and all three files and the web root match the role, with production's modes
4. `landing-deploy`, run as `deploy`, refuses a tarball with no `index.html` and installs only
   `index.html` from one with extras
5. Both hostnames serve that page with all of production's headers, exactly, and redirect port 80
   to HTTPS
6. With all three files changed, check mode reports the drift and changes nothing, then a real run
   repairs them, reloads nginx and leaves the page alone

⚠️ Docker's iptables `FORWARD DROP` blocks `lxdbr0`, and the fix doesn't survive a reboot of the VM.
`test.sh` stops when the container has no network. Re-add the two rules:

```bash
sudo iptables -I DOCKER-USER -i lxdbr0 -j ACCEPT
sudo iptables -I DOCKER-USER -o lxdbr0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
```

## Checking production

**Check mode only, from a Mac terminal**, in a throwaway clone pinned to the reviewed commit. The VM
can't reach the Droplet. A real run is a separate decision for Sean, on a diff Sean has read. Every
difference gets one of two outcomes: fix the role, or record it as deliberate. Production is never
changed to match the role.

```bash
SHA=<the reviewed commit>
tmp=$(mktemp -d) && git -C "$tmp" init -q \
  && git -C "$tmp" fetch -q --depth 1 https://github.com/CaddisMaster/seandesmet.com.git "$SHA" \
  && git -C "$tmp" checkout -q FETCH_HEAD && cd "$tmp/infra/ansible"
brew install python@3.12
"$(brew --prefix python@3.12)/bin/python3.12" -m venv ../.venv \
  && ../.venv/bin/pip install -q --no-deps -r ../requirements-infra.txt && ../.venv/bin/pip check
cp inventory.example.yml inventory.yml
../.venv/bin/ansible-playbook site.yml --check --diff
cd ~ && rm -rf "$tmp"
```

Put the Droplet's address in `inventory.yml`'s `ansible_host` before the `ansible-playbook` line.
ansible-core needs Python 3.12 or newer, and the Mac's default `python3` is older. Collections
aren't needed here: `www_site` uses only `ansible.builtin`.
