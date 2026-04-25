// Shim header. patch_core.cpp `#include "hpatch.h"` expects rn-update's
// android/jni/hpatch.h to be on the include path. We instead vendor a
// zlib-only equivalent at cpp/codepush_hpatch/codepush_hpatch.h. This shim
// lets vendored patch_core.cpp keep its include line untouched.

#pragma once
#include "codepush_hpatch.h"
