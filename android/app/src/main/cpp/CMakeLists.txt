cmake_minimum_required(VERSION 3.22.1)
project(codepush_patch)

# Phase 1 NDK bootstrap. This file currently builds an empty shared library
# so we can confirm the Android module compiles with externalNativeBuild
# enabled before we add the vendored patch_core sources in the next commit.

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(codepush_patch SHARED
    bootstrap_stub.cpp
)

# liblog is the only Android system dep we'll need once JNI lands; declaring
# it now avoids touching the link config in the next commit.
find_library(log-lib log)
target_link_libraries(codepush_patch ${log-lib})
