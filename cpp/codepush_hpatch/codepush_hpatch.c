// codepush_hpatch.c
//
// See codepush_hpatch.h. Adapted from react-native-update's hpatch.c
// (MIT, Copyright 2021 housisong), reduced to a single zlib-only path.
// Patches consumed here MUST be produced with `hdiffz -c-zlib`.

#include "codepush_hpatch.h"
#include "HDiffPatch/libHDiffPatch/HPatch/patch.h"
#include "HDiffPatch/file_for_patch.h"

#define _CompressPlugin_zlib
#define _IsNeedIncludeDefaultCompressHead 0
#include <zlib.h>
#include "HDiffPatch/decompress_plugin_demo.h"

#define kCodePushMaxLoadOldToMem ((1 << 20) * 8)  // 8 MiB

#define _check(v, errorType)                                              \
    do {                                                                  \
        if (!(v)) {                                                       \
            if (result == kCodePushHPatch_ok) result = (errorType);       \
            if (!_isInClear) goto _clear;                                 \
        }                                                                 \
    } while (0)

static hpatch_TDecompress* getDecompressPlugin(const char* compressType) {
    if (zlibDecompressPlugin.is_can_open(compressType)) {
        return &zlibDecompressPlugin;
    }
    return 0;
}

static int hpatch_by_stream(const hpatch_TStreamInput* old,
                            hpatch_BOOL isLoadOldAllToMem,
                            const hpatch_TStreamInput* pat,
                            hpatch_TStreamOutput* out_new,
                            const hpatch_singleCompressedDiffInfo* patInfo) {
    int result = kCodePushHPatch_ok;
    int _isInClear = hpatch_FALSE;
    hpatch_TDecompress* decompressPlugin = 0;
    uint8_t* temp_cache = 0;
    size_t temp_cache_size;
    hpatch_singleCompressedDiffInfo _patinfo;
    hpatch_TStreamInput _old;

    {  // info
        if (!patInfo) {
            _check(getSingleCompressedDiffInfo(&_patinfo, pat, 0),
                   kCodePushHPatch_error_info);
            patInfo = &_patinfo;
        }
        _check(old->streamSize == patInfo->oldDataSize,
               kCodePushHPatch_error_old_size);
        _check(out_new->streamSize >= patInfo->newDataSize,
               kCodePushHPatch_error_new_size);
        out_new->streamSize = patInfo->newDataSize;
        if (strlen(patInfo->compressType) > 0) {
            decompressPlugin = getDecompressPlugin(patInfo->compressType);
            _check(decompressPlugin, kCodePushHPatch_error_compressType);
        }
    }
    {  // mem
        size_t mem_size;
        size_t oldSize = (size_t)old->streamSize;
        isLoadOldAllToMem =
            isLoadOldAllToMem && (old->streamSize <= kCodePushMaxLoadOldToMem);
        temp_cache_size =
            patInfo->stepMemSize + hpatch_kFileIOBufBetterSize * 3;
        mem_size = temp_cache_size + (isLoadOldAllToMem ? oldSize : 0);
        temp_cache = (uint8_t*)malloc(mem_size);
        _check(temp_cache, kCodePushHPatch_error_malloc);
        if (isLoadOldAllToMem) {
            uint8_t* oldMem = temp_cache + temp_cache_size;
            _check(old->read(old, 0, oldMem, oldMem + oldSize),
                   kCodePushHPatch_error_old_fread);
            mem_as_hStreamInput(&_old, oldMem, oldMem + oldSize);
            old = &_old;
        }
    }

    _check(patch_single_compressed_diff(
               out_new, old, pat, patInfo->diffDataPos,
               patInfo->uncompressedSize, decompressPlugin,
               patInfo->coverCount, patInfo->stepMemSize, temp_cache,
               temp_cache + temp_cache_size),
           kCodePushHPatch_error_patch);

_clear:
    _isInClear = hpatch_TRUE;
    if (temp_cache) {
        free(temp_cache);
        temp_cache = 0;
    }
    return result;
}

int hpatch_by_file(const char* oldfile, const char* newfile,
                            const char* patchfile) {
    int result = kCodePushHPatch_ok;
    int _isInClear = hpatch_FALSE;
    int patch_result;
    hpatch_TFileStreamInput oldStream;
    hpatch_TFileStreamInput patStream;
    hpatch_TFileStreamOutput newStream;
    hpatch_TFileStreamInput_init(&oldStream);
    hpatch_TFileStreamInput_init(&patStream);
    hpatch_TFileStreamOutput_init(&newStream);

    _check(hpatch_TFileStreamInput_open(&oldStream, oldfile),
           kCodePushHPatch_error_old_fopen);
    _check(hpatch_TFileStreamInput_open(&patStream, patchfile),
           kCodePushHPatch_error_pat_fopen);
    _check(hpatch_TFileStreamOutput_open(&newStream, newfile,
                                         ~(hpatch_StreamPos_t)0),
           kCodePushHPatch_error_new_fopen);

    patch_result = hpatch_by_stream(&oldStream.base, hpatch_TRUE,
                                    &patStream.base, &newStream.base, 0);
    if (patch_result != kCodePushHPatch_ok) {
        _check(!oldStream.fileError, kCodePushHPatch_error_old_fread);
        _check(!patStream.fileError, kCodePushHPatch_error_pat_fread);
        _check(!newStream.fileError, kCodePushHPatch_error_new_fwrite);
        _check(hpatch_FALSE, patch_result);
    }

_clear:
    _isInClear = hpatch_TRUE;
    _check(hpatch_TFileStreamInput_close(&oldStream),
           kCodePushHPatch_error_old_fclose);
    _check(hpatch_TFileStreamInput_close(&patStream),
           kCodePushHPatch_error_pat_fclose);
    _check(hpatch_TFileStreamOutput_close(&newStream),
           kCodePushHPatch_error_new_fclose);
    return result;
}
