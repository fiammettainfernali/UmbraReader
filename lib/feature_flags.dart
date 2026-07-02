/// App-wide feature flags.
///
/// [kReadAloudEnabled] gates the entire in-app read-aloud feature (the player
/// controls, Listen mode, voice/pronunciation settings, and background audio
/// pre-processing). It's turned off in favour of listening in Speechify via
/// the "Share story" hand-off. Flip it back to `true` to restore the whole
/// feature — the underlying code is left intact.
const bool kReadAloudEnabled = false;
