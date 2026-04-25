// codepush_hpatch.h
//
// Minimal HDiffPatch apply-by-file wrapper used by the CodePush SDK on iOS
// and Android. Adapted from react-native-update's `android/jni/hpatch.{c,h}`
// (MIT, Copyright 2021 housisong) — narrowed to zlib decompression only.
//
// Patches consumed here MUST be produced with `hdiffz -c-zlib`. Both
// platforms link zlib for free (iOS: `-lz` via the SDK's existing
// `s.library = 'z'`; Android NDK: bundled). Avoiding lzma lets us skip
// vendoring sisong/lzma.

#ifndef CODEPUSH_HPATCH_H
#define CODEPUSH_HPATCH_H

#include <stdint.h>
#include "HDiffPatch/libHDiffPatch/HPatch/patch_types.h"

#ifdef __cplusplus
extern "C" {
#endif

enum {
    kCodePushHPatch_ok                 = 0,
    kCodePushHPatch_error_malloc       = -1,
    kCodePushHPatch_error_info         = -2,
    kCodePushHPatch_error_compressType = -3,
    kCodePushHPatch_error_patch        = -4,
    kCodePushHPatch_error_old_fopen    = -5,
    kCodePushHPatch_error_old_fread    = -6,
    kCodePushHPatch_error_old_fclose   = -7,
    kCodePushHPatch_error_pat_fopen    = -8,
    kCodePushHPatch_error_pat_fread    = -9,
    kCodePushHPatch_error_pat_fclose   = -10,
    kCodePushHPatch_error_new_fopen    = -11,
    kCodePushHPatch_error_new_fwrite   = -12,
    kCodePushHPatch_error_new_fclose   = -13,
    kCodePushHPatch_error_old_size     = -14,
    kCodePushHPatch_error_new_size     = -15,
};

/**
 * Applies a single-compressed-diff patch produced by
 * `hdiffz -c-zlib oldfile newfile patchfile` to `oldfile`, writing the
 * reconstructed bytes to `newfile`. Returns 0 on success.
 *
 * Despite the function name, `oldfile` is read-only; `newfile` is
 * overwritten if it exists.
 */
int hpatch_by_file(const char* oldfile, const char* newfile,
                            const char* patchfile);

#ifdef __cplusplus
}
#endif

#endif  // CODEPUSH_HPATCH_H
