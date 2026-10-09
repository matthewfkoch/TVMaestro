fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## tvos

### tvos setup

```sh
[bundle exec] fastlane tvos setup
```

Register bundle ID + App Store Connect app (one-time)

### tvos beta

```sh
[bundle exec] fastlane tvos beta
```

Build Release and upload to TestFlight

### tvos build

```sh
[bundle exec] fastlane tvos build
```

Build App Store IPA locally (no upload)

### tvos metadata

```sh
[bundle exec] fastlane tvos metadata
```

Upload tvOS App Store listing only (no binary, no review submission)

### tvos screenshots

```sh
[bundle exec] fastlane tvos screenshots
```

Upload tvOS screenshots only (no binary, no metadata, no review submission)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
