# seandesmet.com

Sean DeSmet's personal site: a single static `index.html`, no build step, no framework, served by
Nginx off disk on the DigitalOcean Droplet at https://seandesmet.com and https://www.seandesmet.com.
Split out of `CaddisMaster/budget-buddy` under budget-buddy#299.

> ⚠️ **This file is the always-loaded core.** The workflow is the one budget-buddy runs on,
> deliberately — read budget-buddy's `CLAUDE.md` and `CONTRIBUTING.md` for the reasoning behind
> it. What is written here is that workflow **as it applies to a page with no releases**, plus
> the traps specific to this repo.
>
> **The left column is the ACTION, not the topic** — same convention as budget-buddy, for the
> same reason: a trigger you can match against the command you are about to type needs no
> judgement.
>
> | Before you… | Read |
> |---|---|
> | start a session — reconcile against `git log` / `gh issue list` | §Current status below |
> | edit `index.html` | §Non-negotiables below |
> | rename a class, restructure the stack tags, or edit a workflow | [`scripts/check-stack.sh`](scripts/check-stack.sh), and the branch protection note in §Git & development workflow |
> | add any file the page loads (CSS, JS, image, favicon, PDF) | §Non-negotiables → "Only `index.html` reaches the box" |
> | add a `<script>`, a web-font or stylesheet link, an external image, or change a response header | [`scripts/check-csp.sh`](scripts/check-csp.sh) and [`SETUP.md`](SETUP.md) §9 — the CSP blocks it otherwise |
> | write a claim about Budget Buddy's features or stack | budget-buddy's `CLAUDE.md` §Tech Stack |
> | run anything on the Droplet | [`SETUP.md`](SETUP.md) — from a **Mac terminal**, never from the VM |
> | touch certificates or the nginx site file | [`README.md`](README.md) §Certificates and `SETUP.md` §5 |

## Tech stack

- **Page:** one hand-written `index.html` — inline `<style>`, no JavaScript, light/dark via
  `prefers-color-scheme` (both token sets in `:root`), the "Engineer's notebook" design (#19)
- **Fonts:** IBM Plex Sans and JetBrains Mono, **embedded as base64** — Google Fonts' own Latin
  subset files, **unmodified**. ⚠️ Do not re-subset or optimise them: IBM Plex carries the Reserved
  Font Name "Plex" under the OFL, so a modified copy could not keep the name. The subsets have no
  `→` or `↗`, which is why those arrows are inline SVG
- **Serving:** Nginx on the Droplet, web root `/var/www/seandesmet.com`, Let's Encrypt certificate
  with its own lineage (separate from `budget.seandesmet.com`)
- **Deploy:** GitHub Actions (`deploy.yml`) → SSH with a key restricted to one forced command
- **Checks:** `scripts/check-stack.sh` and `scripts/check-csp.sh`, run on every PR (`check.yml`)
  and again before every deploy
- **Response headers:** HSTS, a strict CSP and five more, from
  `/etc/nginx/snippets/seandesmet-security-headers.conf` on the box — `SETUP.md` §9 (#29)

## Project map

```
index.html                    # THE page — the only file that is deployed
README.md                     # why the repo exists, how deploy works, certificates
SETUP.md                      # one-time Droplet setup runbook (run from a Mac)
CLAUDE.md                     # this file
.github/workflows/deploy.yml  # stack-tag gate → copy to Droplet → byte-for-byte live verify
.github/workflows/check.yml   # the same gate on every pull request
scripts/check-stack.sh        # THE stack-tag gate — one file, run by both workflows
scripts/check-csp.sh          # the page side of the server's CSP — same two workflows
```

## Non-negotiables

**Merging to `main` IS the deploy**
- A push to `main` touching `index.html`, `deploy.yml` or `scripts/check-stack.sh` deploys within a
  minute. There is **no
  Release gate** as budget-buddy has — so there is no "merge now, finish later"
- ⚠️ **Every merged PR must leave the live page presentable.** Build the revamp in slices that
  each stand on their own. **Not a long-lived `revamp` branch** — budget-buddy avoids those for
  good reasons (revert granularity, bisect, review), and they apply here unchanged
- A PR touching only docs (`CLAUDE.md`, `README.md`, `SETUP.md`) triggers no deploy

**Only `index.html` reaches the box**
- The workflow tars **only `index.html`**, and the forced command on the Droplet installs **only
  `index.html`**, whatever the tarball contains. The live verify then compares **only
  `index.html`** — so a `style.css`, `favicon.svg`, headshot or résumé PDF added beside it is
  **dropped silently while the deploy goes green**, and the live page shows a broken reference
- So: CSS stays inline; icons are inline `<svg>`; fonts, the favicon or a small image are `data:` URIs.
  Anything genuinely too big to inline (a résumé PDF, a photo) needs its **own issue** that changes
  the workflow, `SETUP.md` §2's receiving script, *and* the verify step together — the script
  change is run by Sean from a Mac, not from a session

**The deploy gate reads the markup**
- `scripts/check-stack.sh` greps `<span class="stack-tag">…</span>` and **fails if fewer than 5
  match**.
  A redesign that renames that class or restructures the tags fails the deploy with a message
  about the selector. Change the check **in the same PR** as the markup, and keep its
  "matched nothing" assertion — an absence check that cannot fail is worse than none
- The stack tags are **factual claims about each project**. Check them against that project's own
  docs (budget-buddy's `CLAUDE.md`; material-list-import-tool's `README.md` §Tech stack) before
  writing one — the page advertised Chart.js for four releases after the app
  dropped it (budget-buddy#291)

**The page**
- Must work, and look deliberate, in **light and dark** and at **~400px wide**
- Accessible by default: semantic landmarks, one `<h1>`, visible `:focus-visible`, expandable
  controls carry `aria-expanded`, icon-only links carry an accessible name, WCAG AA contrast
- External links to Sean's own properties only. `target="_blank"` needs `rel="noopener"`
- **No third-party requests — and the server now enforces it.** nginx sends
  `default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:` (#29), so a web
  font, analytics, a CDN or any `<script>` is **blocked in the visitor's browser with no error
  anywhere a maintainer looks**. `scripts/check-csp.sh` fails the PR instead. If something is
  genuinely needed: an issue, then the policy in `SETUP.md` §9 and on the box, **then** the page
- ⚠️ **The Budget Buddy screenshot is SAMPLE DATA and must stay that way** (#25). It is a WebP
  `data:` URI of the local dev stack, logged in as a `portfolio-demo` user created by budget-buddy's
  `scripts/seed_dev.py` — never a real account, never production. To retake it: seed that user
  (`docker compose exec web python scripts/seed_dev.py --username portfolio-demo`, `--force` to
  reset), capture Home at 1280px in dark mode, crop to the top 745px, encode WebP ~0.8.
  ⚠️ **Loading Home can make a billed model call**: when the month has no cached AI read, the page's
  own script requests one right after load. Nothing in the markup looks like it — it cost one call
  the first time. Retake against a user whose month already has a read, or with the AI key unset
- ⚠️ **The Material List Import Tool card is an OUTLINE of a PRIVATE project** (#27), and that
  project's `README.md` is the authority for what it may say. **Never name the employer** (Sean's
  call — it is not deployed and waits on their IT and data-governance review), **never add a
  screenshot** (a useful one is a real builder's takeoff), **never link the repo**, and no
  builder, store, job or item names. The first-run figures are the README's published aggregate
  only. Any new claim is checked against that README first, not written from memory
- ⚠️ **This repo is public.** No email address, phone number or home address in markup —
  LinkedIn is the contact route (#7). Nothing from `CLAUDE.local.md` belongs in any tracked file

**Process**
- **Verify locally before every PR** (below). There is no test suite; the gate only checks the
  stack tags, and the live verify only proves the bytes arrived — neither looks at the page
- **No `CHANGELOG.md` and no GitHub Releases** — a deliberate difference from budget-buddy, not an
  omission (README §Deploying, budget-buddy#288). The page has no versions; the squash-merged
  history is the record
- **Automated issue triage does not exist here** — no `triage` label, no triage workflow

## Verifying locally

```bash
python3 -m http.server 8000     # then open http://localhost:8000
```

Look at it, rather than assuming — CI never renders the page:

- light **and** dark (browser devtools → rendering → `prefers-color-scheme`)
- ~400px wide, and a desktop width
- keyboard only: Tab through every link and button, and operate every toggle
- every link goes where it says

If the change touches the stack tags or their markup, run `scripts/check-stack.sh` before pushing.
It takes a path, so its failure paths can be exercised on a scratch copy without editing the page.

## Git & development workflow

Same rule as budget-buddy. Rationale lives in budget-buddy's `CONTRIBUTING.md` §2.

**Issue → branch → PR → squash-merge.** `main` is **protected** (#23): a direct push is rejected,
admins included, and a PR cannot merge until **The tech stack names nothing retired** and **The
page fits the server's CSP** (#29) both pass.
⚠️ The protection rule requires those checks **by their job names** — renaming a job in
`check.yml` without updating the rule leaves every PR waiting on a check that never reports. There is no
approval requirement: a sole maintainer cannot approve their own PR.

1. **Every change starts from an issue** — no issueless PRs. Feature issues carry Gherkin
   acceptance criteria. Assign the open milestone
2. **Branch** off `main` as `<issue#>-short-slug`
3. **Verify locally** (above)
4. **Open a PR** with `Closes #<issue>`, one line per issue, and squash-merge once the check is
   green. The gate only reads the stack tags — a green PR says nothing about how the page looks,
   which is why step 3 exists
5. **After merge, check the Deploy run on `main`**: `gh run list --workflow Deploy --limit 1`.
   A green run means the live page is byte-identical to `index.html`. Read a red one before
   re-running it

**Milestones = projects, not releases.** budget-buddy's milestones are released versions; this
repo has none, so a milestone is a body of work, closed when its last issue is live. The same
discipline carries over: **exactly one open at a time**, assigned when the issue is filed, and an
issue closed `NOT_PLANNED` gets none.

**Batch issues into PRs by COHERENCE, never by calendar.** A PR may close several issues only when
they share a surface or one visitor-facing story. In a one-file repo *everything* shares a file,
so the test that matters is the story: "header and links" is one PR; "header" and "meta tags" are
two.

**Commit messages:** imperative mood, capitalised subject, no trailing period, ~72 columns. The body
says **why** — the diff already shows what.

**Delegation:** don't. budget-buddy delegates when *reading* is the expensive part; here the whole
codebase is one ~7 KB file.

### End of session

budget-buddy's `/wrap`, minus what does not exist here:

1. PR open for the locally verified unit(s), `Closes #n`
2. Merged → Deploy run on `main` checked, not assumed
3. **Notes in ONE pass, at the very end** — where they live is in `CLAUDE.local.md`. Not present
   means a fresh clone; skip it and say so
4. Report in three or four lines: what merged, what is live, what is still open, what next

## The Revamp

✅ **Shipped 2026-09-16; milestone closed.** **Goal:** the page should read as a professional
portfolio — a visitor learns who Sean is, what Sean builds, and where to see the code, within one
screen.

| Item | Shipped |
|---|---|
| `CLAUDE.md` and `.gitignore` | #3 (closes #1) |
| **GitHub** link in the header; Budget Buddy card links **Live** and **Source** separately | #4 (#2) |
| The card's repo link as a labelled **GitHub** button with the mark, replacing "Source" — Sean's pick over showing the repo path | #18 (#17) |
| **LinkedIn** link — and an email link, since removed | #6 (#5), #8 (#7) |
| Accessibility: `h1`/landmarks, Details `aria-expanded`, four contrast failures fixed, reduced motion | #10 (#9) |
| Metadata: description, Open Graph, `twitter:card`, canonical, `theme-color`, "SD" favicon `data:` URI | #12 (#11) |
| **About** section, and labelled About / Projects sections | #14 (#13) |
| **Redesign — "Engineer's notebook"**: dot-grid ground, Plex Sans + JetBrains Mono embedded, request-path diagram on the card, light and dark token sets | #20 (#19) |

**Sean's decisions, 2026-09-16 — standing, and the copy is Sean's, not a session's to rewrite:**

- **Contact is LinkedIn only — no email.** #5 added one and #7 removed it: a published address
  draws spam
- **No résumé and no photo** — so nothing needs to change about the single-file deploy
- **The headline stays "Full stack projects."** Three alternatives were offered and declined. The
  `<title>`, description and Open Graph tags are built from it, so a headline change touches all
  of them
- **The About text** is the one Sean chose from three drafts. Change it only on Sean's say-so
- **No `og:image`** — it would be a separate deployed file, and link unfurlers reject `data:` URIs
- **The look is direction B, "Engineer's notebook"**, chosen over an editorial serif and a split
  two-column layout. Dark is the design's home; the light set was derived from it
- **Fonts are embedded, not linked** — no request to Google or anyone else

**Standing decisions that must not be re-opened:** the decisions above; one file, no build step,
no framework; no changelog and no Releases; history was not subtree-split from budget-buddy; the
deploy key is not Budget Buddy's and never will be; never re-run certbot or copy a lineage name out
of a document.

## Current status

⚠️ **This section lags `main` by construction.** Reconcile against `git log` and `gh issue list` at
the start of every session. An open issue is not evidence of open work — **read the comments**, not
just the body, before proposing one.

- **2026-09-16:** the Revamp shipped across PRs #3–#20 — content, accessibility, metadata, then
  the "Engineer's notebook" redesign (#20) — and its milestone is **closed**
- **2026-09-17:** **Showcase and hardening** shipped and its milestone is **closed**: PR checks and
  `main` protection (#23 → #24), the Budget Buddy screenshot with sample data (#25 → #26), the
  Material List Import Tool outline card (#27 → #28), and security headers (#29 → #30).
  ✅ **`SETUP.md` §9 is APPLIED on the box** — run by Sean from the Mac on 2026-09-17 and verified
  live: all seven headers on both hostnames and on a 404, no nginx version, `charset=utf-8`, and the
  live page rendered under the real CSP with zero violations. budget.seandesmet.com was unaffected.
  ⚠️ So the CSP is **live**: `scripts/check-csp.sh` is guarding a real policy, not a planned one
- **No milestone is open**; the next body of work opens one. After every merge the Deploy run was
  green and both hostnames were byte-identical to `index.html` on `main`
- **Nothing is broken and waiting.** Anything next is new scope, and new scope starts with an issue

## Maintainer notes (local only)

The maintainer's notes, Droplet access and vault paths live in the gitignored `CLAUDE.local.md`,
not in this repo — same line as budget-buddy. The standing rule it carries is **do all
note-writing in ONE pass at the very end of a session**. A fresh clone is fully functional
without it.
