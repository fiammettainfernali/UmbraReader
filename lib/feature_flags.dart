/// App-wide feature flags.
///
/// [kReadAloudEnabled] gates the entire in-app read-aloud feature (the player
/// controls, Listen mode, voice/pronunciation settings, and background audio
/// pre-processing). Re-enabled to drive a self-hosted Chatterbox voice server
/// (the "Natural" engine) — natural narration generated on the user's own
/// desktop GPU, cached per paragraph, playable offline.
const bool kReadAloudEnabled = true;
