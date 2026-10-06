# First Homebrew onboarding

The upstream repository follows the tap's stable universal release contract.
These templates prepare integration; they do not publish or edit the tap.

1. Commit/merge the app, then use `make release` and wait for its Release workflow
   to succeed. Confirm the release's DMG, ZIP, `SHA256SUMS`, and attestations.
2. Download the **published** assets into a fresh directory, then generate a cask:

   ```sh
   gh release download v0.1.0 --repo laixintao/gazelift --dir dist/published-v0.1.0 \
     --pattern '*.dmg' --pattern '*.zip' --pattern SHA256SUMS
   python3 scripts/prepare-tap.py --artifact-dir dist/published-v0.1.0
   ```

   Use a checkout matching that release. Do not substitute hashes from a locally
   rebuilt package; even the same source can produce a different DMG checksum.
3. In `laixintao/homebrew-tap`, copy `dist/tap/Casks/gazelift.rb` into `Casks/gazelift.rb`,
   merge the generated JSON entry into `packages.json`, and add GazeLift to the
   README table (macOS 14+, Apple Silicon or Intel) and uninstall examples.
4. Add `laixintao/tap/gazelift` to both install and uninstall commands in the tap's
   `.github/workflows/ci.yml`. No legacy override is needed.
5. Run the tap's updater tests, `brew style`, strict audit, and install/uninstall
   tests on Apple Silicon and Intel, as required by its release standard:

   ```sh
   python3 -m unittest discover -s tests -v
   brew style Casks/gazelift.rb
   brew audit --cask --strict --skip-style --tap=laixintao/tap
   brew install --cask laixintao/tap/gazelift
   brew uninstall --cask laixintao/tap/gazelift
   ```

6. After onboarding, the tap's existing six-hour updater handles new stable
   releases automatically. Run its Update casks workflow manually for an
   immediate sync. No cross-repository write token is needed.

The cask quits `io.xbin.gazelift` on uninstall and removes local preferences only
when users explicitly request `--zap`. It does not remove quarantine attributes.
