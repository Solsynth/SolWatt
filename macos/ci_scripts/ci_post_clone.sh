#!/bin/sh

# Xcode Cloud runs this script after cloning the repository, before Xcode
# builds macos/Runner.xcworkspace. It installs the toolchain the archive needs
# and generates the Xcode configuration, so the build phase does not have to.

# Fail this script if any subcommand fails.
set -e

# The default execution directory is macos/ci_scripts/. Move to the repository root.
cd "$CI_PRIMARY_REPOSITORY_PATH"

echo "=== Installing Flutter SDK ==="
# Clone the stable Flutter SDK from Git into the home folder
git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$HOME/flutter"
export PATH="$PATH:$HOME/flutter/bin"

# Pre-cache macOS artifacts and fetch dependencies
flutter precache --macos
# Retry + HTTP/1.1: the Socommon git dependencies clone from src.solsynth.dev
# behind Cloudflare, which intermittently resets large pack transfers (curl 56).
git config --global http.version HTTP/1.1
for attempt in 1 2 3; do
  flutter pub get && break
  echo "flutter pub get failed (attempt $attempt); retrying in 10s"
  sleep 10
done

echo "=== Installing Rust ==="
# super_context_menu depends on super_native_extensions, whose Rust crate is
# compiled by Dart native-assets hooks (native_toolchain_rust) while Xcode
# builds the target; there is no CocoaPod for it. Those hooks shell out to
# rustup, so rustup has to exist in the build environment, and the crate pins
# the channel and target list it needs in its own rust-toolchain.toml.
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain none
export PATH="$HOME/.cargo/bin:$PATH"

# Install the pinned toolchain and its targets up front. rustup resolves
# rust-toolchain.toml from the working directory and installs the channel, the
# profile and the whole target list it names, which is what the build hook
# expects to find later on.
rust_prepared=""
for toolchain_file in "$HOME"/.pub-cache/hosted/pub.dev/super_native_extensions-*/rust/rust-toolchain.toml; do
  [ -f "$toolchain_file" ] || continue
  (cd "$(dirname "$toolchain_file")" && rustup toolchain install)
  rust_prepared=yes
done
if [ -z "$rust_prepared" ]; then
  echo "warning: super_native_extensions is not in the pub cache, so the Rust" >&2
  echo "warning: toolchain was not pre-downloaded; the build hook will fetch it" >&2
fi

echo "=== Installing CocoaPods ==="
# Disable homebrew auto-updates to save CI time
HOMEBREW_NO_AUTO_UPDATE=1 brew install cocoapods

# Install macOS pods
echo "=== Running Pod Install ==="
cd macos
pod install --repo-update

# The distribution configuration the GitHub workflows pass as --dart-define is
# baked into macos/Flutter/ephemeral/Flutter-Generated.xcconfig here, which the
# archive's build phase then reads. Forward the values when the Xcode Cloud
# workflow defines them and keep the defaults compiled into the app when it does
# not. Neither value contains whitespace.
dart_defines=""
for name in DISTRIBUTION_API_BASE_URL DISTRIBUTION_PRODUCT_ID; do
  value=$(printenv "$name" || :)
  if [ -n "$value" ]; then
    dart_defines="$dart_defines --dart-define=$name=$value"
  fi
done

# Return to the root and generate the configurations the archive reads
# (macos/Flutter/ephemeral/Flutter-Generated.xcconfig, FlutterMacOS.podspec)
# without building twice.
cd "$CI_PRIMARY_REPOSITORY_PATH"
flutter build macos --config-only $dart_defines

echo "=== Script finished successfully ==="
exit 0
