// codepush_patch_jni.cpp
//
// JNI binding for the CodePush Android patch applier. The Java side
// (CodePushHDiffPatchApplier.java) does ZIP extraction, manifest parsing,
// file copies, hash + signature verification, and metadata persistence.
// The only thing it needs from native code is the bundle binary diff
// apply step itself, which we expose as a single function below.

#include <jni.h>
#include <string>
#include "codepush_hpatch.h"

extern "C" JNIEXPORT jstring JNICALL
Java_com_microsoft_codepush_react_CodePushHDiffPatchApplier_applyBundlePatchNative(
    JNIEnv* env,
    jclass /*clazz*/,
    jstring originBundlePath_,
    jstring newBundlePath_,
    jstring patchFilePath_) {

    const char* originBundlePath =
        env->GetStringUTFChars(originBundlePath_, nullptr);
    const char* newBundlePath =
        env->GetStringUTFChars(newBundlePath_, nullptr);
    const char* patchFilePath =
        env->GetStringUTFChars(patchFilePath_, nullptr);

    int rc = hpatch_by_file(originBundlePath, newBundlePath, patchFilePath);

    env->ReleaseStringUTFChars(originBundlePath_, originBundlePath);
    env->ReleaseStringUTFChars(newBundlePath_, newBundlePath);
    env->ReleaseStringUTFChars(patchFilePath_, patchFilePath);

    if (rc != kCodePushHPatch_ok) {
        std::string message =
            "hpatch_by_file failed with code " + std::to_string(rc);
        return env->NewStringUTF(message.c_str());
    }
    return nullptr;  // success
}
