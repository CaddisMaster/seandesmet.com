# seandesmet.com

The static landing page served at **https://seandesmet.com** and **https://www.seandesmet.com**.
One file, no build step, no framework. Nginx serves it off disk from the Droplet.

## Why this repo exists

It used to live in [`CaddisMaster/budget-buddy`](https://github.com/CaddisMaster/budget-buddy)
as `landing/`, which coupled a personal portfolio page to an unrelated application:

- landing-page issues consumed Budget Buddy's issue numbers and milestones
  (budget-buddy#279, #287, #291);
- landing-page changes had to answer Budget Buddy's `CHANGELOG.md` rule, which forced a
  "delete the entry or write `### Removed`" judgement for a page that has no versions
  (budget-buddy#288);
- `landing/` counted as an *inert* path to that repo's CI classifier, so a landing-only PR
  skipped the expensive jobs and met them for the first time after merge (budget-buddy#281);
- one nginx site file held both server blocks, so a Budget Buddy config mistake could take
  this page down with it.

Split out under budget-buddy#299.

### Provenance

History was deliberately **not** subtree-split — this is a single 7 KB file and the rewrite was
not worth it. The page's full history is in the old repo:

```
git log --follow -- landing/
```

The commits that shaped it: `9eb93ef` (#293, name ApexCharts not Chart.js), `a76b9ec` (#288,
remove the ai-atlas card after that project was abandoned), `f76b3b7` (#280, add it),
`27cd3ea` (#45, retire Mealie and Uptime Kuma), and the initial commit `33376fc`.

## Deploying

**Push to `main` and that is the deploy.** `.github/workflows/deploy.yml` copies `index.html`
to the Droplet and then verifies the live page is byte-identical to the file it just pushed.

There is no GitHub Release gate, unlike Budget Buddy — the page has no versions, so a Release
would carry nothing.

### Deploy setup

The workflow fails closed and names the missing piece, so it is safe to merge before any of
this exists. Four things are needed on the `production` environment:

| Kind | Name | Value |
|---|---|---|
| Secret | `DEPLOY_SSH_KEY` | private half of a **new** key — do **not** reuse Budget Buddy's |
| Secret | `DROPLET_HOST` | the Droplet address |
| Secret | `DROPLET_KNOWN_HOSTS` | `ssh-keyscan` output, so the host key is pinned |
| Variable | `DROPLET_USER` | the deploying user |

⚠️ **The key must be restricted with a forced command.** The workflow deliberately sends a
tarball on stdin and names no destination path, so the *server* decides where bytes land and a
leaked key cannot write anywhere else. Same shape as the backup pull's restricted key.

On the Droplet, the receiving script:

```sh
# /usr/local/bin/landing-deploy   (chmod 755, owned by root)
#!/bin/sh
set -e
exec tar -xzf - -C /var/www/seandesmet.com
```

and the key's entry in that user's `~/.ssh/authorized_keys`:

```
command="/usr/local/bin/landing-deploy",no-agent-forwarding,no-port-forwarding,no-pty,no-X11-forwarding ssh-ed25519 AAAA... landing-deploy
```

⚠️ **Add the nginx site file for this page to BOTH backup config path lists** — the Droplet's
`/usr/local/bin/budget-buddy-backup` and the VM's `droplet-backup.sh`. They are separate copies
with nothing syncing them, and they have drifted before. Miss this and the configs tarball
silently stops covering this page's config.

## Certificates

Apex and `www` already have their own certbot lineage, separate from `budget.seandesmet.com`.

⚠️ **Read the lineage name with `certbot certificates` on the box.** Do not re-run certbot, and
do not copy a lineage name out of any document — a stale hardcoded lineage is budget-buddy#295.
