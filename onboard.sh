#!/usr/bin/env bash
#
# Lanesurf terminal onboarding.
#
#   Run me with process substitution (NOT `curl | bash`):
#
#     bash <(curl -fsSL https://raw.githubusercontent.com/Lanesurf/onboard/v1/onboard.sh)
#
# What I do:
#   1. install prereqs (uv, omni, gh, jq; check git/node/claude)
#   2. log you in with Google via Omnigent (only @lanesurf.com)
#   3. confirm you're on the onboarding allowlist
#   4. authenticate you to GitHub
#   5. clone the Lanesurf workspace into ~/lanesurf
#   6. install `lsf <repo>` so you can make a per-user worktree on demand
#   7. drop you into the workspace, ready to run your own `claude`
#
# Your work lands on branch user/<you>; push it and Sarthak picks it up.

set -euo pipefail

# ───────────────────────── Stage 0: config (Sarthak edits this) ─────────────
OMNI_SERVER="https://v5pq2ya5wm.us-east-1.awsapprunner.com"
WORKSPACE="$HOME/lanesurf"
GH_ORG="Lanesurf"
REPOS=(lanesurf-backend-go outbound-agent inbound-phone-agent platform-dashboard admin-dashboard unified-tms-integrations)
ALLOWLIST_REPO="Lanesurf/onboard-allowlist"
ALLOWLIST_PATH="emails.txt"
TOKENS="$HOME/.omnigent/auth_tokens.json"

# ───────────────────────── helpers ─────────────────────────────────────────
say(){ printf '\033[36m[onboard]\033[0m %s\n' "$*"; }
die(){ printf '\033[31m[onboard] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }
ensure_path(){ case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH";; esac; }

[ -t 0 ] || die "Run me as:  bash <(curl -fsSL <url>)  — not 'curl | bash'. I need your terminal for the login prompts."

OS="$(uname -s)"
ensure_path

# ───────────────────────── Stage 1: prereqs (idempotent, no-sudo first) ─────
say "checking prerequisites…"

have git || {
  if [ "$OS" = Darwin ]; then xcode-select --install 2>/dev/null || true
    die "git missing — finish the Xcode Command Line Tools install that just opened, then re-run."
  else die "git missing — install it (e.g. 'sudo apt-get install -y git') then re-run."; fi
}

have uv || { say "installing uv…"; curl -LsSf https://astral.sh/uv/install.sh | sh; ensure_path; }
have uv || die "uv install failed — see https://docs.astral.sh/uv/"

have omni || { say "installing omnigent…"; uv tool install omnigent; ensure_path; }
have omni || die "omni install failed"

have jq || {
  say "installing jq…"
  if [ "$OS" = Darwin ] && have brew; then brew install jq
  elif have apt-get; then sudo apt-get install -y jq || die "install jq, then re-run"
  elif have dnf; then sudo dnf install -y jq || die "install jq, then re-run"
  else die "jq required — install it (https://jqlang.github.io/jq/) then re-run"; fi
}

have gh || {
  if [ "$OS" = Darwin ] && have brew; then say "installing gh…"; brew install gh
  else die "GitHub CLI (gh) required — install from https://cli.github.com then re-run"; fi
}

have tmux || say "note: tmux not found (optional — only needed for multi-session workflows)."
if ! { have node && [ "$(node -pe 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)" -ge 22 ]; }; then
  say "note: Node 22+ not found — install with fnm/mise/brew if your repo needs it."
fi
have claude || { say "installing Claude Code…"; curl -fsSL https://claude.ai/install.sh | bash || say "Claude Code install skipped — install it yourself later."; ensure_path; }

# persist ~/.local/bin on PATH for future shells (pick the user's login shell rc)
case "${SHELL:-}" in
  */zsh) RC="$HOME/.zshrc" ;;
  */bash) RC="$HOME/.bashrc" ;;
  *) RC="$HOME/.profile" ;;
esac
grep -q 'omnigent onboarding PATH' "$RC" 2>/dev/null || \
  printf '\n# omnigent onboarding PATH\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$RC"

# ───────────────────────── Stage 2: Google login via omni ──────────────────
if [ -f "$TOKENS" ] && jq -e --arg s "${OMNI_SERVER%/}" \
     'any(to_entries[]; (.key|rtrimstr("/"))==$s and (.value.token != null))' "$TOKENS" >/dev/null 2>&1; then
  say "already signed in to Omnigent."
else
  say "signing you in with Google — a browser window will open (if not, copy the URL printed below)…"
  omni login "$OMNI_SERVER" || die "Google sign-in failed or was cancelled."
fi
[ -f "$TOKENS" ] || die "no Omnigent token found — sign-in did not complete."

# ───────────────────────── Stage 3: read identity ──────────────────────────
EMAIL="$(jq -r --arg s "${OMNI_SERVER%/}" \
          'first(to_entries[] | select((.key|rtrimstr("/"))==$s) | .value.user_id) // empty' "$TOKENS")"
[ -n "$EMAIL" ] || die "couldn't read your email from the Omnigent token (is the server in OIDC mode?)."
say "signed in as $EMAIL"

# ───────────────────────── Stage 4: GitHub auth ────────────────────────────
if ! gh auth status >/dev/null 2>&1; then
  say "connecting your GitHub account (needed to clone the private repos)…"
  gh auth login --hostname github.com --git-protocol https --web --scopes "repo,read:org" \
    || die "GitHub sign-in failed."
fi
gh auth setup-git
gh auth status >/dev/null 2>&1 || die "GitHub auth is not active."

# ───────────────────────── Stage 5: allowlist check (curation) ─────────────
# Hard boundary is the server's @lanesurf.com domain-lock (Stage 2). This is
# curation: the list lives in a PRIVATE repo, fetched with your GitHub token.
say "checking the onboarding allowlist…"
ALLOW="$(gh api "repos/$ALLOWLIST_REPO/contents/$ALLOWLIST_PATH" \
          -H 'Accept: application/vnd.github.raw' 2>/dev/null || true)"
[ -n "$ALLOW" ] || die "couldn't read the allowlist — ask Sarthak to grant you access to $ALLOWLIST_REPO."
if ! printf '%s\n' "$ALLOW" | grep -vE '^[[:space:]]*(#|$)' | grep -qixF "$EMAIL"; then
  die "$EMAIL is not on the onboarding allowlist yet. Ask Sarthak to add you."
fi
say "you're on the allowlist ✓"

# ───────────────────────── Stage 6: clone workspace ────────────────────────
mkdir -p "$WORKSPACE"
for r in "${REPOS[@]}"; do
  d="$WORKSPACE/$r"
  if [ -d "$d/.git" ]; then say "updating $r…"; git -C "$d" fetch --quiet origin || true
  else say "cloning $r…"; gh repo clone "$GH_ORG/$r" "$d" -- --quiet || die "clone failed: $r"; fi
done

# ───────────────────────── Stage 7: per-user branch + lsf helper ───────────
LOCAL="${EMAIL%@*}"
SLUG="$(printf '%s' "$LOCAL" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed 's/--*/-/g; s/^-//; s/-$//')"
BRANCH="user/$SLUG"
printf 'WORKSPACE=%s\nGH_ORG=%s\nBRANCH=%s\nSLUG=%s\nEMAIL=%s\nREPOS="%s"\n' \
  "$WORKSPACE" "$GH_ORG" "$BRANCH" "$SLUG" "$EMAIL" "${REPOS[*]}" > "$WORKSPACE/.onboard-session"

cat > "$HOME/.local/bin/lsf" <<'LSF'
#!/usr/bin/env bash
# lsf <repo> — create (if needed) and enter YOUR per-user worktree for a repo.
set -euo pipefail
SESS="$HOME/lanesurf/.onboard-session"
[ -f "$SESS" ] || { echo "no onboard session — run the onboarding link first" >&2; exit 1; }
# shellcheck disable=SC1090
. "$SESS"
repo="${1:-}"
[ -n "$repo" ] || { echo "usage: lsf <repo>   (one of: $REPOS)" >&2; exit 1; }
root="$WORKSPACE/$repo"
[ -d "$root/.git" ] || { echo "unknown/uncloned repo: $repo" >&2; exit 1; }
git -C "$root" fetch --quiet origin || true
if git -C "$root" show-ref --verify --quiet refs/heads/dev \
   || git -C "$root" show-ref --verify --quiet refs/remotes/origin/dev; then base=dev; else base=main; fi
wt="$WORKSPACE/${repo}-${SLUG}"
if [ ! -d "$wt" ]; then
  if git -C "$root" show-ref --verify --quiet "refs/heads/$BRANCH" \
     || git -C "$root" show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
    git -C "$root" worktree add "$wt" "$BRANCH"
  else
    git -C "$root" worktree add -b "$BRANCH" "$wt" "$base"
  fi
fi
echo "→ $wt  (branch $BRANCH)"
cd "$wt" && exec "$SHELL" -l
LSF
chmod +x "$HOME/.local/bin/lsf"

# ───────────────────────── done ────────────────────────────────────────────
say "✅ all set."
say "workspace : $WORKSPACE"
say "your branch: $BRANCH   (push it; Sarthak checks it out to take over)"
say ""
say "next:   lsf lanesurf-backend-go      # makes your worktree for that repo"
say "then:   claude                       # your own Claude Code, in the worktree"
say ""
cd "$WORKSPACE"
exec "$SHELL" -l
