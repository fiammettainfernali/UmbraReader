# umbra_reader

A Flutter e-reader for Novel Grabber's OPDS library.

## Building an Android release

```
flutter build apk --release --split-per-abi
```

**Always with `--split-per-abi`.** Without it one universal APK carries
native libraries for all three Android architectures, and this app bundles
ONNX Runtime for the semantic index (see `lib/services/text_embedder.dart`),
whose native library is the largest thing in the build. Measured on the same
commit:

| build | size |
|---|---|
| universal (3 ABIs) | 170.0 MB |
| `app-arm64-v8a-release.apk` | 71.1 MB |
| `app-armeabi-v7a-release.apk` | 61.0 MB |
| `app-x86_64-release.apk` | 78.2 MB |

Install `app-arm64-v8a-release.apk` on any modern phone; x86_64 is for
emulators. The ABI filters are deliberately NOT pinned in Gradle, because
that would drop the emulator build along with the waste.

Note the 23 MB embedding model in `assets/models/minilm/` is committed to
the repo, so a clone builds without fetching anything. Git LFS would be the
tidier home for it if the history ever needs slimming.

## Getting Started

A few resources if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
