# One-time Droplet setup

Everything here runs **from a Mac terminal**. The `jupiter` VM is deliberately unable to reach
the Droplet (Dev Environment Isolation Plan, Phase 2) and that stays true — nothing in this
file is meant to be run from the VM.

Work top to bottom. **Nothing is removed until the replacement is verified serving**, so the
old page keeps serving right up to §7, and §8 is the only irreversible step.

---

## 0. Set the variables and confirm you can reach the box

⚠️ **Run this — it is a step, not a legend.** Every later command uses `$DROPLET`. Unset, `ssh`
takes the *script* as the hostname and fails with `hostname contains invalid characters`,
having connected to nothing. (Harmless, but confusing: it looks like the script is malformed
when the variable is simply empty.)

```sh
DROPLET=root@147.182.219.112
WEBROOT=/var/www/seandesmet.com

ssh $DROPLET "echo connected as \$(whoami)"    # expect: connected as root
```

⚠️ These are shell variables, not exports — **a new terminal loses them.** If you come back to
this later, or open a second tab, run this section again first.

---

## 1. Generate the deploy key (on the Mac)

A **new** key. Do not reuse Budget Buddy's — that one opens production, and the whole point of
a separate key is that this one cannot.

```sh
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_landing -N '' -C 'landing-deploy'
```

Two halves, two destinations: the **private** half goes into a GitHub secret (§6), the
**public** half into `authorized_keys` (§4).

## 2. Install the receiving script (on the Droplet)

```sh
ssh $DROPLET 'cat > /usr/local/bin/landing-deploy <<'"'"'EOF'"'"'
#!/bin/sh
# The ONLY thing the landing deploy key can run. The client sends a tarball on
# stdin and names no destination — this script decides where bytes land, so a
# leaked key cannot write anywhere else.
set -eu
TMP=$(mktemp -d)
trap "rm -rf \"$TMP\"" EXIT
# Extract into a scratch dir, never straight into the web root: a crafted
# tarball with ../ components is then contained, and a partial transfer never
# leaves a half-written page being served.
tar -xzf - -C "$TMP" --no-same-owner --no-same-permissions
[ -f "$TMP/index.html" ] || { echo "landing-deploy: expected index.html" >&2; exit 1; }
install -m 0644 "$TMP/index.html" /var/www/seandesmet.com/index.html
echo "landing-deploy: installed index.html ($(stat -c%s "$TMP/index.html") bytes)" >&2
EOF
chmod 755 /usr/local/bin/landing-deploy'
```

⚠️ Only `index.html` is ever written, whatever the tarball contains. That is deliberate — it
is what makes the key safe to hold in GitHub.

## 3. Create the web root and seed it

Outside `/opt/budget-buddy`, which is the point: the portfolio's uptime stops living inside the
app's directory.

```sh
ssh $DROPLET "mkdir -p $WEBROOT \
  && cp /opt/budget-buddy/landing/index.html $WEBROOT/index.html \
  && chown -R deploy:deploy $WEBROOT \
  && chmod 755 $WEBROOT && chmod 644 $WEBROOT/index.html \
  && ls -la $WEBROOT"
```

## 4. Authorize the key, restricted to that one command

⚠️ **Set the two variables on their own lines first.** An earlier revision of this file wrapped
one `ssh` command across three lines with backslash continuations inside a double-quoted string;
a single stray space after a backslash silently changes what gets appended, and this line is the
security boundary. Assign, then use — the `ssh` call stays on one line.

```sh
PUBKEY="$(cat ~/.ssh/id_ed25519_landing.pub)"
OPTS='command="/usr/local/bin/landing-deploy",no-agent-forwarding,no-port-forwarding,no-pty,no-X11-forwarding,restrict'

ssh $DROPLET "printf '%s %s\n' '$OPTS' '$PUBKEY' >> ~deploy/.ssh/authorized_keys"
```

**Verify the line parsed**, rather than assuming it did. A malformed options field is the one
mistake here that could leave the key unrestricted:

```sh
ssh $DROPLET 'ssh-keygen -l -f ~deploy/.ssh/authorized_keys'
# the landing key's fingerprint must appear — compare with:
ssh-keygen -lf ~/.ssh/id_ed25519_landing.pub

ssh $DROPLET 'tail -2 ~deploy/.ssh/authorized_keys | cat -A | cut -c1-120'
# cat -A makes trailing whitespace and stray backslashes visible
```

**Then prove the key is confined.** A green deploy proves the key works, never that it cannot do
anything else:

```sh
ssh -i ~/.ssh/id_ed25519_landing deploy@147.182.219.112 'cat /etc/shadow' < /dev/null
```

Expected:

```
gzip: stdin: unexpected end of file
tar: Child returned status 1
tar: Error is not recoverable: exiting now
```

The client's command is discarded and `landing-deploy` runs instead, which reads a tarball from
stdin and finds an empty stream. **What matters is that `/etc/shadow` is not printed.**

⚠️ **`< /dev/null` is not optional.** Without it, stdin is your terminal, `tar` waits for a
tarball that never arrives, and the session appears to hang. That is the forced command working
correctly — press Ctrl-C. (An earlier revision of this file omitted the redirect and predicted
`landing-deploy: expected index.html`, which is what you get from a *valid* tarball that has no
`index.html` in it, not from an empty stream.)

**If the line is malformed**, delete it and redo the append above. Only lines mentioning
`landing-deploy` match, so the backup key (`backup-export` / `jupiter-backup`) is untouched:

```sh
ssh $DROPLET "sed -i.bak '/landing-deploy/d' ~deploy/.ssh/authorized_keys \
  && chown deploy:deploy ~deploy/.ssh/authorized_keys \
  && chmod 600 ~deploy/.ssh/authorized_keys \
  && cat ~deploy/.ssh/authorized_keys"
```

⚠️ The `chown`/`chmod` are not decoration — `sed -i` run as root leaves the file root-owned, and
sshd's `StrictModes` is particular about this file.

## 5. Split the nginx config

The apex/www block currently lives **inside** `/etc/nginx/sites-available/budget-buddy`,
alongside the app. Both halves of this section happen before one `nginx -t`, because two
enabled server blocks claiming `seandesmet.com` makes nginx pick one arbitrarily and warn.

**Back up first**, so rollback is a copy rather than a reconstruction:

```sh
ssh $DROPLET 'cp /etc/nginx/sites-available/budget-buddy /root/budget-buddy.nginx.bak'
```

**Read the live certificate lineage** — do not copy a name out of any document, including this
one. A hardcoded stale lineage is budget-buddy#295:

```sh
ssh $DROPLET 'certbot certificates'
# pick the lineage whose SAN covers BOTH seandesmet.com and www.seandesmet.com
```

Write `/etc/nginx/sites-available/seandesmet.com` with the two blocks moved out of
`budget-buddy` — the 443 block and the certbot HTTP redirect — changing only `root`, and
substituting the lineage you just read for `<LINEAGE>`:

```nginx
server {
  server_name seandesmet.com www.seandesmet.com;
  root /var/www/seandesmet.com;
  index index.html;
  location / { try_files $uri $uri/ =404; }

  listen 443 ssl;
  ssl_certificate     /etc/letsencrypt/live/<LINEAGE>/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/<LINEAGE>/privkey.pem;
  include             /etc/letsencrypt/options-ssl-nginx.conf;
  ssl_dhparam         /etc/letsencrypt/ssl-dhparams.pem;
}

server {
  if ($host = seandesmet.com) { return 301 https://$host$request_uri; }
  listen 80;
  server_name seandesmet.com www.seandesmet.com;
  return 404;
}
```

Then **delete those same two blocks** from `sites-available/budget-buddy`, leaving only the
`budget.seandesmet.com` blocks, and enable the new site:

```sh
ssh $DROPLET 'ln -sf /etc/nginx/sites-available/seandesmet.com /etc/nginx/sites-enabled/ \
  && nginx -t'
```

`nginx -t` **before** any reload, always. Only if it passes:

```sh
ssh $DROPLET 'systemctl reload nginx'
```

## 6. Configure GitHub

On this repo's **`production`** environment:

```sh
gh secret set DEPLOY_SSH_KEY      --repo CaddisMaster/seandesmet.com --env production < ~/.ssh/id_ed25519_landing
gh secret set DROPLET_HOST        --repo CaddisMaster/seandesmet.com --env production --body '147.182.219.112'
ssh-keyscan -H 147.182.219.112 2>/dev/null | gh secret set DROPLET_KNOWN_HOSTS --repo CaddisMaster/seandesmet.com --env production
gh variable set DROPLET_USER      --repo CaddisMaster/seandesmet.com --env production --body 'deploy'
```

## 7. Verify, before removing anything

```sh
curl -sS https://seandesmet.com/      | md5sum
curl -sS https://www.seandesmet.com/  | md5sum
# both must equal:
md5sum index.html   # accea4d55fcffc984b777e6a2195994b at the initial commit
```

⚠️ Compare a **hash**, not the absence of an error string — an absence check passes just as
happily against an nginx error page.

Then exercise the pipeline end to end:

```sh
gh workflow run Deploy --repo CaddisMaster/seandesmet.com
gh run watch --repo CaddisMaster/seandesmet.com
```

The workflow verifies the live page is byte-identical to `index.html` itself, so a green run
is the real signal.

## 8. Only now, clean up

The irreversible step. Everything above must be green first.

```sh
ssh $DROPLET 'rm -rf /opt/budget-buddy/landing && ls /opt/budget-buddy'
```

The old `/root/budget-buddy.nginx.bak` from §5 can go once you are happy.

Budget Buddy's own cleanup (deleting `landing/`, dropping its drift check) is
budget-buddy#299 step 6 — a separate PR in that repo, after this is all done.

## 9. Security headers (#29)

✅ **Applied 2026-09-17** and verified live (#29). Kept here as the record of what is on the box, and
for a rebuild; re-running it is harmless.

Added after the split — run it once, any time after §8. Like everything in this file it runs
**from the Mac**, and nothing here touches `budget.seandesmet.com`: only the `seandesmet.com` site
file changes.

It adds seven response headers, hides the nginx version, and declares `charset=utf-8`. The
reasoning behind each value is in #29; the one that matters most is the
**Content-Security-Policy**, which only works because the page loads nothing but `data:` URIs:

```
default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:;
base-uri 'none'; form-action 'none'; frame-ancestors 'none'
```

⚠️ **That policy is a contract with `index.html`.** A script, a web-font link or an external image
added to the page would be silently blocked in every visitor's browser. `scripts/check-csp.sh`
enforces the page side on every PR and before every deploy; this section is the server side. If the
page ever genuinely needs more, change the policy **here and on the box first**.

⚠️ **HSTS is a one-year promise.** Once a browser has seen it, it refuses plain HTTP for
`seandesmet.com` for a year and will not let a visitor click through a certificate error. That is
the point — but it means an expired certificate becomes a hard outage rather than a warning.
certbot's renewal is what keeps that promise. `includeSubDomains` is deliberately **not** set, so
no other subdomain is bound by it.

**Run §0 first** if this is a new terminal — every command uses `$DROPLET`.

### 9a. Look before changing anything

```sh
ssh $DROPLET 'cat /etc/nginx/sites-available/seandesmet.com; echo ---; grep -n add_header /etc/nginx/sites-available/seandesmet.com || echo "no add_header lines"'
```

Expect the file from §5 and **`no add_header lines`**. ⚠️ If there are any, stop and ask: nginx does
not merge `add_header` across levels, so an existing one inside a `location` block would silently
drop every header this section adds, for that location.

### 9b. Write the snippet

Written whole, from a quoted heredoc, so nothing in it is expanded or re-quoted on the way:

```sh
ssh $DROPLET 'cat > /etc/nginx/snippets/seandesmet-security-headers.conf' <<'EOF'
# Security headers for seandesmet.com. Managed from the seandesmet.com repo,
# SETUP.md §9 (#29) — change it there first.
# The CSP is a contract with index.html: no scripts, inline styles only, fonts
# and images as data: URIs. scripts/check-csp.sh enforces the page side.
server_tokens off;
charset utf-8;
add_header Strict-Transport-Security "max-age=31536000" always;
add_header Content-Security-Policy "default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'" always;
add_header X-Content-Type-Options "nosniff" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=(), usb=()" always;
add_header X-Frame-Options "DENY" always;
add_header Cross-Origin-Opener-Policy "same-origin" always;
EOF
ssh $DROPLET 'cat /etc/nginx/snippets/seandesmet-security-headers.conf'
```

The second command prints it back. Check the CSP line survived intact, single quotes included.

### 9c. Include it, test, and reload — or restore

One script, sent as a quoted heredoc so none of it is interpreted by the Mac's shell. It refuses to
guess: it adds the `include` only when the HTTPS block's `root` line appears **exactly once**, backs
the file up first, and **restores the backup and does not reload** if `nginx -t` fails. Running it
twice is harmless.

```sh
ssh $DROPLET 'bash -s' <<'EOF'
set -eu
SITE=/etc/nginx/sites-available/seandesmet.com
INC='include /etc/nginx/snippets/seandesmet-security-headers.conf;'

if grep -qF "$INC" "$SITE"; then
  echo "already included — testing only"
  nginx -t
  exit 0
fi

n=$(grep -c '^[[:space:]]*root /var/www/seandesmet.com;' "$SITE" || true)
if [ "$n" != 1 ]; then
  echo "expected exactly one 'root /var/www/seandesmet.com;' line, found $n — stopping, nothing changed" >&2
  exit 1
fi

cp "$SITE" /root/seandesmet.com.nginx.pre-headers.bak
sed -i "s|^\([[:space:]]*\)root /var/www/seandesmet.com;|&\n\1$INC|" "$SITE"

if nginx -t; then
  systemctl reload nginx
  echo "reloaded"
else
  cp /root/seandesmet.com.nginx.pre-headers.bak "$SITE"
  echo "nginx -t FAILED — restored the previous file, nothing reloaded" >&2
  exit 1
fi

grep -n -B1 -A1 'security-headers' "$SITE"
EOF
```

Expect `syntax is ok`, `test is successful`, `reloaded`, and the `include` line printed directly
under `root /var/www/seandesmet.com;`.

### 9d. Verify

```sh
curl -sSI https://seandesmet.com/     | grep -iE 'server|content-type|strict-transport|content-security|x-content|referrer|permissions|x-frame|cross-origin'
curl -sSI https://www.seandesmet.com/ | grep -ciE 'strict-transport|content-security|x-content|referrer|permissions|x-frame|cross-origin'   # expect: 7
curl -sSI https://budget.seandesmet.com/ | head -1                                                                                       # expect: unchanged
```

Expect `Server: nginx` with **no version**, `Content-Type: text/html; charset=utf-8`, and all seven
headers. Then tell Claude — a session can read the live headers and render the page under the
real policy from the VM, since that needs no access to the box.

### 9e. Roll back, if ever needed

```sh
ssh $DROPLET 'sed -i "\|seandesmet-security-headers.conf|d" /etc/nginx/sites-available/seandesmet.com && nginx -t && systemctl reload nginx'
```

That removes every header at once. Browsers that already saw HSTS keep enforcing HTTPS until their
year runs out, which is harmless while the certificate stays valid.

---

## What you do NOT need to do

⚠️ **The backup config lists need no edit.** budget-buddy#299 says a new nginx site file must
be added to both or the configs tarball silently stops covering it. That is **not correct** —
both lists name whole directories:

```
/etc/nginx/sites-available
/etc/nginx/sites-enabled
```

in `/usr/local/bin/backup-export` (the forced command the VM's pull triggers) and in
`/usr/local/bin/budget-buddy-backup` (the Droplet's own timer job). A new site file inside
those directories is captured automatically.

The web root's *contents* are not backed up, and should not be — `index.html` is in git, the
same reason `/opt/budget-buddy/landing` was never in the list either.

⚠️ Verified against the `infra/` copies in personal-vault, which `CLAUDE.local.md` warns are
unsynced copies of what is actually on the box. Worth one `grep -n 'sites-available'` on the
real scripts while you are there.
