# Security

Overdrive reads system state and, when you ask it to, deletes caches or moves files to the Trash. Bugs in that second part matter, so please report them privately.

## Reporting

Email rashforddamion@gmail.com with "Overdrive security" in the subject, or use GitHub's private vulnerability reporting on this repository. Include the version (Overdrive › About), the edition, and steps to reproduce. You will get a reply within 7 days and a fix or mitigation plan within 30 days for confirmed issues.

Please do not open a public issue for anything that could delete or expose someone's files before a fix ships.

## Scope

- Any path by which a cleanup, uninstall, trash or orphan-blob action could touch files outside the folders it lists.
- Symlink or path-traversal escapes out of the home folder (`CleanupEngine.isSafeTarget` is the guard; its tests are in `Tests/OverdriveCoreTests/CleanupTests.swift`).
- Administrator tasks in the direct edition executing anything other than the fixed commands in `MaintenanceCatalog`.
- Network behavior that is not documented in the privacy policy.

## What Overdrive does not do

It never runs with root, never installs helpers, daemons or kernel extensions, never phones home, and never deletes a person's own documents outright (large files, downloads, app leftovers and startup items go to the Trash).
