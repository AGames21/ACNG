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
the separate request for a release. Releases carry only `dist/acng-freeroam.zip` and its `.build.json` from `tools/build_freeroam.py`
at a pushed commit. Never attach Spa, the personal AC car zip or any game asset.

```powershell
python tools/build_freeroam.py
gh release create <tag> dist/acng-freeroam.zip dist/acng-freeroam.build.json -R AGames21/ACNG --title <title> --notes-file <notes>
```

Verify by downloading the asset again and comparing its SHA256 with the manifest.

### Every release is a beta (maintainer request, 2026-10-11)

ACNG is not finished, so every GitHub release is published as a **pre-release** until the
maintainer asks for a stable one. Tags use semantic versions with a beta suffix:
`v0.3.0-beta`, then `v0.3.1-beta` for fixes and `v0.4.0-beta` for new features; a second
build of the same version is `v0.3.0-beta.2`. Add `--prerelease` to `gh release create`.
The README links to `/releases`, not `/releases/latest`, because GitHub's "latest" skips
pre-releases. The two date-tagged builds (`freeroam-2026-10-08`, `freeroam-2026-10-09`)
were switched to pre-releases at the same request.

Release stages, for reference: pre-alpha (internal experiments), alpha (features still
arriving and changing), beta (playable, features may still change, bugs expected),
release candidate (believed ready, final checks only), stable release.

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
- The maintainer chose the MIT licence and asked to make the repository public
  on 2026-10-08.
