# Normal-profile installation

The user explicitly authorized installing ACNG in the normal BeamNG profile on
2026-10-08. That instruction supersedes the earlier isolated-profile-only rule for
this installation. The original game installation, unrelated mods and controls
remain unchanged by the installer.

`scripts/install_normal.py --confirm-normal` checks the registered normal profile,
refuses a running game or an ambiguous prior ACNG copy, validates the player ZIP
and every manifest hash, and backs up settings (including saves), vehicle configs
and the mod database outside the game profile. It adds one ACNG control app to the
existing freeroam layout and copies the verified ZIP. All eight existing apps and
placements were preserved during this installation.

The exact backup path and install manifest are ignored local records:
`.local/normal-install.json`. Backup contents never belong in GitHub. Keep only one
ACNG package active; updates need a deliberate backup/replacement review rather
than rerunning the first-install command.

N001 is a temporary local setup helper: load an offline West Coast USA scene,
exercise the native master ON/OFF button while parked, and verify Road heat/wear,
OFF unload, telemetry OFF and preference saving. It does not drive or spawn AI.
The helper is retired outside the mod folder after verification, so future game
launches do not run setup again. Actual user driving and broad third-party car
compatibility remain separate tests.

Rollback with BeamNG closed: move only the installed `mods/acng-freeroam.zip` to
the recorded backup, restore the saved freeroam layout, and remove only newly
created ACNG-specific settings if desired. Do not restore the whole settings tree
over newer saves or reset unrelated mods. The backup is recovery evidence, not a
reason to overwrite subsequent user work.
