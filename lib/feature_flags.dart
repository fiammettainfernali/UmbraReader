/// App-wide feature flags.
///
/// [kReadAloudEnabled] gates the entire in-app read-aloud feature (the player
/// controls, Listen mode, voice/pronunciation settings, and background audio
/// pre-processing). Hidden again in favour of listening in Natural Reader via
/// the "Share story" .epub hand-off. All the underlying code (the on-device
/// and self-hosted Chatterbox/Kokoro `NetworkTtsService` engines, request
/// pacing, rolling prefetch, client-side speed) is left intact — flip to
/// `true` to restore the whole feature.
const bool kReadAloudEnabled = false;
