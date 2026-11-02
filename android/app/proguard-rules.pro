# Keep rules for the release build's code shrinker.
#
# ONNX Runtime (the semantic index's inference engine) is the reason this
# file exists. Its native library looks its OWN Java classes up by name
# through JNI — FindClass/GetMethodID on strings, at runtime. Nothing in
# Dart or Java references those classes, so R8 correctly concludes they are
# unreachable and removes them. The native side then gets null back and
# calls JniAbort, which kills the process outright rather than throwing
# something Dart could catch.
#
# The symptom was an app that would not open at all: every inference goes
# through checkOrtStatus, every call to it aborted, and the indexer runs on
# every library load. It appears only in release builds, so no test, no
# analysis and no debug run can see it coming.
-keep class ai.onnxruntime.** { *; }
-keepclassmembers class ai.onnxruntime.** { *; }

# Native methods are bound by name; renaming them breaks the binding.
-keepclasseswithmembernames class * {
    native <methods>;
}

# JNI constructs exceptions by signature when a status check fails, so the
# constructors have to survive even where the class is otherwise unused.
-keep class ai.onnxruntime.OrtException { *; }
