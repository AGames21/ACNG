# GitHub checkpoint

The user authorized creating a GitHub repository on 2026-10-08. Default to a private
personal repository named ACNG. Do not change visibility, force-push, overwrite an
existing repository, or publish a release without a separate request.

The local GitHub CLI is installed but was not authenticated at setup. Run
`gh auth login` and complete the user's browser authorization, then check
`gh auth status`. Credentials never belong in the project or Obsidian.

Before upload, run `python tools/publication_audit.py`, inspect Git status and
tracked paths, and confirm any staged files belong to ACNG. The audit scans current
tracked files for prohibited game binaries/private directories and all reachable
Git blobs for known credential formats. It is a targeted check, not a comprehensive
privacy guarantee. Local profiles, private paths, logs, raw capture runs and built
ZIPs stay ignored. Committed research screenshots and benchmark summaries are
original evidence; no extracted game models, textures or binaries are included.

After checking that the account has no conflicting ACNG repository:

```powershell
gh repo create ACNG --private --source . --remote origin --push
git ls-remote origin refs/heads/main
```

Compare the remote main hash with local HEAD. Record the verified URL and commit
in the existing Obsidian project notes. Do not claim upload success from a local
commit or configured remote alone.
