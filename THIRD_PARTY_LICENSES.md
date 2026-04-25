# Third-Party Licenses

This SDK vendors source from two upstream projects, both MIT-licensed.
Both copies live under `cpp/` and are not modified beyond stripping
unused files (see `tools/sync-vendored-cpp.sh`).

---

## react-native-update — `cpp/patch_core/`

Subset lifted: `archive_patch_core.{h,cpp}`, `patch_core.{h,cpp}`,
`state_core.{h,cpp}`, `tests/patch_core_test.cpp`.

`patch_core_android.cpp` and `update_core_android.cpp` are intentionally
**not** vendored — they are upstream's Android JNI bindings; we ship our
own at `android/app/src/main/cpp/`.

> MIT License
>
> Update Plugin for React Native
> Copyright (c) Wuhan Charmlot Network Technology Co., Ltd.
>
> Permission is hereby granted, free of charge, to any person obtaining a
> copy of this software and associated documentation files (the "Software"),
> to deal in the Software without restriction, including without limitation
> the rights to use, copy, modify, merge, publish, distribute, sublicense,
> and/or sell copies of the Software, and to permit persons to whom the
> Software is furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included
> in all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
> THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
> OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
> ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
> OTHER DEALINGS IN THE SOFTWARE.

Source: <https://github.com/reactnativecn/react-native-update>

---

## sisong/HDiffPatch — `cpp/HDiffPatch/`

Pinned tag: **v4.9.0**. The on-device build (CMakeLists.txt) only compiles
the apply-side primitives (`libHDiffPatch/HPatch/`, `libParallel/`,
`file_for_patch.c`); diff-side tools and `hdiffz` are not built but remain
in the tree for reproducibility.

**Server-client version contract:** the rnota worker's Dockerfile MUST
pin `hdiffz` to the same tag. Patch format compatibility is not
guaranteed across HDiffPatch majors.

> MIT License
>
> HDiffPatch
> Copyright (c) 2012-2023 housisong
>
> Permission is hereby granted, free of charge, to any person obtaining a
> copy of this software and associated documentation files (the "Software"),
> to deal in the Software without restriction, including without limitation
> the rights to use, copy, modify, merge, publish, distribute, sublicense,
> and/or sell copies of the Software, and to permit persons to whom the
> Software is furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included
> in all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
> THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
> OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
> ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
> OTHER DEALINGS IN THE SOFTWARE.

Source: <https://github.com/sisong/HDiffPatch>
