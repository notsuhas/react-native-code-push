cmake_minimum_required(VERSION 3.22.1)
project(codepush_patch)

# Phase 1: build the native side of the HDiffPatch apply path.
#
# The source list below is **explicit** — never use file(GLOB) on the
# vendored cpp/ tree. patch_core's upstream may re-acquire its Android
# JNI bindings during a re-sync; the `tools/sync-vendored-cpp.sh` script
# explicitly forbids those files but defense-in-depth here too.

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(REPO_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../../../../..)

# Vendored archive-aware patch core (rn-update, MIT)
set(PATCH_CORE_SOURCES
    ${REPO_ROOT}/cpp/patch_core/patch_core.cpp
    ${REPO_ROOT}/cpp/patch_core/archive_patch_core.cpp
    ${REPO_ROOT}/cpp/patch_core/state_core.cpp
)

# CodePush-owned hpatch wrapper (zlib only)
set(CODEPUSH_HPATCH_SOURCES
    ${REPO_ROOT}/cpp/codepush_hpatch/codepush_hpatch.c
)

# Vendored sisong/HDiffPatch v4.9.0 — apply-side primitives only
set(HDIFFPATCH_SOURCES
    ${REPO_ROOT}/cpp/HDiffPatch/file_for_patch.c
    ${REPO_ROOT}/cpp/HDiffPatch/libHDiffPatch/HPatch/patch.c
    ${REPO_ROOT}/cpp/HDiffPatch/libParallel/parallel_channel.cpp
    ${REPO_ROOT}/cpp/HDiffPatch/libParallel/parallel_import.cpp
)

add_library(codepush_patch SHARED
    codepush_patch_jni.cpp
    ${PATCH_CORE_SOURCES}
    ${CODEPUSH_HPATCH_SOURCES}
    ${HDIFFPATCH_SOURCES}
)

target_include_directories(codepush_patch PRIVATE
    ${REPO_ROOT}/cpp
    ${REPO_ROOT}/cpp/codepush_hpatch
    ${REPO_ROOT}/cpp/patch_core
    ${REPO_ROOT}/cpp/HDiffPatch
    ${REPO_ROOT}/cpp/HDiffPatch/libHDiffPatch
)

# zlib is bundled in the Android NDK; we link it for codepush_hpatch.c's
# zlib decompress plugin. liblog is for any future logging from native.
find_library(log-lib log)
find_library(zlib-lib z)
target_link_libraries(codepush_patch ${log-lib} ${zlib-lib})
