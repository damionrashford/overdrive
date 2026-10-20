# Homebrew tap for Overdrive

This folder is the content of the `damionrashford/homebrew-tap` repository. Copy it there once; after that the release workflow keeps `Casks/overdrive.rb` current when a `TAP_TOKEN` secret (a fine-grained token with contents write access to the tap repository) is set on the main repository.

```sh
brew tap damionrashford/tap
brew install --cask --no-quarantine overdrive
brew upgrade --cask overdrive
brew uninstall --cask --zap overdrive
```
