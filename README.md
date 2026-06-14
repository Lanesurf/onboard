# Lanesurf onboarding

One command sets up a teammate's Lanesurf dev environment: Google sign-in, the
full repo workspace, and a personal git worktree to work in — then they hand
their branch off to Sarthak.

## Run it

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Lanesurf/onboard/v1/onboard.sh)
```

> Use `bash <(curl ...)`, **not** `curl ... | bash` — the script needs your
> terminal for the Google + GitHub sign-in prompts.

Verify the script before running (optional but encouraged):

```bash
curl -fsSL https://raw.githubusercontent.com/Lanesurf/onboard/v1/onboard.sh | shasum -a 256
# compare against the sha256 Sarthak posted in Slack
```

## What it does

1. Installs prereqs (`uv`, `omni`, `gh`, `jq`; checks `git`/`node`/`claude`).
2. Signs you in with Google via Omnigent — only `@lanesurf.com` accounts.
3. Confirms you're on the onboarding allowlist.
4. Connects your GitHub account (separate from Google — needed to clone).
5. Clones the Lanesurf workspace into `~/lanesurf`.
6. Installs `lsf <repo>` — makes your personal worktree for a repo on demand.
7. Drops you into `~/lanesurf`, ready to run your own `claude`.

## Working + handoff

```bash
lsf lanesurf-backend-go        # creates ~/lanesurf/lanesurf-backend-go-<you> on branch user/<you>
claude                         # your own Claude Code, in that worktree
# …work, commit…
git push -u origin user/<you>  # hand off — Sarthak checks out your branch
```

## Maintenance (Sarthak)

- **Add/remove a teammate:** edit `emails.txt` in the private `Lanesurf/onboard-allowlist` repo. No change here, no redeploy.
- **Change the repo set:** edit `REPOS=(...)` in `onboard.sh`, then bump the tag (`v2`, …) and re-publish the link.
- **Security note:** the hard access boundary is the Omnigent server's `@lanesurf.com` domain-lock. The `emails.txt` allowlist is curation and is bypassable by a determined `@lanesurf.com` insider. For hard per-email enforcement, front the server with an auth proxy.
