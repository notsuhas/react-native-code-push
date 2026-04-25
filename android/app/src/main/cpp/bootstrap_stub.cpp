// Phase 1 NDK bootstrap placeholder.
//
// This file exists to give CMake one source so libcodepush_patch.so links
// while the Android NDK build is being introduced. The next commit replaces
// it with the real JNI binding (codepush_patch_jni.cpp) and pulls in the
// vendored patch_core + HDiffPatch sources.

#include <jni.h>

extern "C" JNIEXPORT void JNICALL
Java_com_microsoft_codepush_react_CodePushHDiffPatchApplier_bootstrapStub(
    JNIEnv*, jclass) {
    // No-op. Replaced in the next commit.
}
