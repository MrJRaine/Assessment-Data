---
name: reference_gh_cli_token_via_git
description: gh CLI shows "not logged in" on this machine, but git DOES have a working GitHub credential — borrow it via GH_TOKEN and gh operations (PRs, api) work. Don't tell the user you "can't" without trying this.
metadata:
  type: feedback
---

On this machine `gh auth status` reports **"not logged into any GitHub hosts"** and bare `gh pr` / `gh api` calls fail — **but git itself has a working GitHub credential** (Git Credential Manager), which is why `git push` / `git fetch` succeed. gh and git use SEPARATE credential stores, so gh being "unauthenticated" does NOT mean GitHub CLI operations are impossible. Borrow git's credential per-command:

```bash
token=$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill 2>/dev/null | sed -n 's/^password=//p')
GH_TOKEN="$token" gh pr create --base main --head <branch> --title "..." --body "..."
```

The borrowed token (as of 2026-08-27) has scopes `repo`, `workflow`, `gist` — enough for PR create/list/view and most `gh api` calls. It lacks `read:org` (only matters for org-level queries). Never print the token: redact `gho_` / `ghp_` / `github_pat_` in any command output.

**Why:** On 2026-08-27 I twice told the user "gh isn't authenticated" and fell back to the manual compare-link for opening a PR, implying it couldn't be done from the CLI — the borrow-from-git workaround was available the whole time. The user asked me to hold onto this "for the next time you tell me you can't."

**How to apply:** Before telling the user you can't do a `gh` / GitHub-CLI action, try lending git's credential via `GH_TOKEN`. Generalize it: when any tool reports "not authenticated," check whether an adjacent tool on the machine already holds a usable credential (git ↔ gh, az ↔ a service principal, etc.) before declaring the action impossible. "Tool X isn't logged in" is a fact about tool X, not a verdict on whether the operation can be done.
