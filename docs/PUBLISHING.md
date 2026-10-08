# GitHub checkpoint

Created and verified 2026-10-08: **https://github.com/AGames21/ACNG**, private,
default branch main, full local history uploaded. Custom original SVG banner,
native control-app screenshot, evidence-backed README, repository topics and bug/
driving feedback templates are included. No public visibility or release upload.

The CLI's combined `--source . --push` path could not discover the local repository.
Creating the repository without `--source`, then adding the HTTPS origin and using
native Git worked. For HTTPS pushes, the command-local helper
`git -c credential.helper= -c 'credential.helper=!gh auth git-credential' push`
uses GitHub CLI authentication without changing global Git credential settings.

The user authorized creating a GitHub repository on 2026-10-08. Default to a private
personal repository named ACNG. Do not change visibility, force-push, overwrite an
existing repository, or publish a release without a separate request.

The local GitHub CLI is installed and now authenticated; it was not authenticated at setup. Run
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

## Releases for the user's other PCs

On 2026-10-08 the user asked to get the whole mod on their other PCs, which is
the separate request for a release. Releases stay in the private repository and
carry only `dist/acng-freeroam.zip` and its `.build.json` from `tools/build_freeroam.py`
at a pushed commit. Never attach Spa, the personal AC car zip or any game asset.

```powershell
python tools/build_freeroam.py
gh release create <tag> dist/acng-freeroam.zip dist/acng-freeroam.build.json -R AGames21/ACNG --title <title> --notes-file <notes>
```

Verify by downloading the asset again and comparing its SHA256 with the manifest.

## Public readiness (2026-10-08)

The user asked to get this repository ready to make public. Checked before any
visibility change:

- Every reachable Git blob scanned for personal paths, emails, LAN addresses and
  tokens: none. All commits use the generic `ACNG Engineering` identity. Older
  revisions of AGENTS.md still mention the maintainer's notebook path and that they
  were using other apps; no secrets. Removing that from history would need a
  force-push, which is not authorized.
- AGENTS.md now holds only public engineering rules. The maintainer's private
  workspace notes moved to the ignored `.local/AGENTS.local.md`, which AGENTS.md
  tells agents to read first.
- No game assets, maps, cars, binaries or game logs are tracked or attached to
  releases. Spa and the personal AC car live only in the maintainer's separate
  private repository.
- Licence and the actual visibility switch are the maintainer's decisions.
