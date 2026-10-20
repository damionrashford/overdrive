# Overdrive Privacy Policy

Last updated: October 20, 2026

Overdrive is a system monitor and cleaner for macOS. It is free, open source, and designed so that nothing about you or your Mac leaves your Mac.

## What Overdrive collects

Nothing. Overdrive has no account system, no analytics, no crash reporting, no advertising identifiers and no telemetry of any kind. The developer receives no data from the app.

## What Overdrive reads on your Mac

To do its job, Overdrive reads system information locally: CPU, memory, GPU, disk and network statistics from the kernel and the IORegistry; the list of your own running processes; battery and sensor readings; the contents of folders you choose for cleanup, uninstalling or the storage map; and, if a local AI runtime such as Ollama or LM Studio is running, the models it reports on `127.0.0.1`. All of this stays in memory on your Mac and is shown to you. Nothing is stored except your preferences and, in the App Store edition, the security-scoped bookmark for the folder you granted.

## Network access

Overdrive makes no network requests, with two local exceptions and one optional one:

- It talks to local AI runtimes only on the loopback address `127.0.0.1` (Ollama on port 11434, LM Studio on port 1234, llama.cpp on 8080) to list loaded models. These connections never leave your Mac.
- If you turn on "Show public IP" on the Network page (off by default), Overdrive sends one request to `api64.ipify.org` to display your public IP address. That service receives your IP address, which is inherent to any internet request. Turn the option off and no such request is made.

## Files Overdrive changes

Overdrive only changes files when you ask it to and confirm: cleaning caches and logs you selected, moving your own files to the Trash, uninstalling an app you chose, or removing orphaned model blobs. It never deletes your documents outright; large files, downloads and app leftovers are moved to the Trash, where they can be restored.

## Administrator tasks (direct edition only)

Some maintenance tasks in the direct edition run standard macOS commands with administrator rights through the macOS authorization dialog. Overdrive never stores your password; macOS handles the prompt.

## Children

Overdrive is a general-purpose utility and does not knowingly collect information from anyone, including children.

## Changes

If this policy changes, the new version is published at the same address with an updated date. The source code is public, so any change in behavior is visible there as well.

## Contact

Questions: open an issue at https://github.com/damionrashford/overdrive/issues.
