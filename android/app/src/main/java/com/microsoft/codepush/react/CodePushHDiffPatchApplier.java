package com.microsoft.codepush.react;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.text.Normalizer;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;
import java.util.zip.ZipInputStream;

/**
 * Android counterpart to ios/CodePush/CodePushHDiffPatchApplier.mm.
 *
 * Same algorithm — extract patch ZIP into a jailed tmp dir with Zip Slip /
 * symlink / collision defenses, sanity-check `__diff.json` hashes, copy
 * non-manifest entries into the new package folder, run `hpatch_by_file`
 * on the bundle via JNI, walk manifest copies from the previous package
 * folder, resolve the relative bundle path, verify hash + signature
 * (mirroring CodePushUpdateManager.downloadPackage's branches), and
 * persist `app.json`. Failure cleans up `newFolderPath` so the JS layer's
 * full-bundle fallback finds an empty hash-keyed slot.
 */
public final class CodePushHDiffPatchApplier {

    static {
        System.loadLibrary("codepush_patch");
    }

    private static final String MANIFEST_FILE_NAME = "__diff.json";

    public static class CodePushPatchApplyException extends Exception {
        public CodePushPatchApplyException(String message) { super(message); }
        public CodePushPatchApplyException(String message, Throwable cause) { super(message, cause); }
    }

    /**
     * Applies the patch ZIP at {@code patchZipPath} on top of the previous
     * package at {@code currentFolderPath}, producing a fully-formed new
     * package folder at {@code newFolderPath}. Throws on any failure;
     * caller is expected to fall back to the full-ZIP download path.
     */
    public static void applyPatch(
            JSONObject updatePackage,
            String patchZipPath,
            String currentFolderPath,
            String newFolderPath,
            String baseHash,
            String expectedBundleFileName,
            String publicKey
    ) throws CodePushPatchApplyException {
        String expectedHash = updatePackage.optString(
                CodePushConstants.PACKAGE_HASH_KEY, null);
        if (expectedHash == null || expectedHash.isEmpty()) {
            throw new CodePushPatchApplyException("Update package is missing packageHash.");
        }
        if (currentFolderPath == null || !new File(currentFolderPath).exists()) {
            throw new CodePushPatchApplyException(
                    "Current package folder does not exist; cannot patch.");
        }

        File unzipDir = new File(System.getProperty("java.io.tmpdir"),
                "codepush-patch-" + UUID.randomUUID());
        boolean succeeded = false;

        try {
            // 1. Extract patch ZIP with safety defenses.
            extractZipSafely(patchZipPath, unzipDir);

            // 2. Read __diff.json.
            File manifestFile = new File(unzipDir, MANIFEST_FILE_NAME);
            if (!manifestFile.exists()) {
                throw new CodePushPatchApplyException("Patch ZIP missing __diff.json.");
            }
            JSONObject manifest;
            try {
                manifest = new JSONObject(FileUtils.readFileToString(manifestFile.getAbsolutePath()));
            } catch (IOException | JSONException e) {
                throw new CodePushPatchApplyException("Patch __diff.json is malformed.", e);
            }

            // 3. Sanity-check hashes + required fields.
            String fromHash = manifest.optString("fromPackageHash", "");
            String toHash = manifest.optString("toPackageHash", "");
            String bundleEntry = manifest.optString("bundleEntry", "");
            String bundlePatchEntry = manifest.optString("bundlePatchEntry", "");
            if (!fromHash.equals(baseHash)) {
                throw new CodePushPatchApplyException(
                        "Patch fromPackageHash does not match installed package hash.");
            }
            if (!toHash.equals(expectedHash)) {
                throw new CodePushPatchApplyException(
                        "Patch toPackageHash does not match expected target hash.");
            }
            if (bundleEntry.isEmpty() || bundlePatchEntry.isEmpty()) {
                throw new CodePushPatchApplyException(
                        "Patch manifest missing bundleEntry or bundlePatchEntry.");
            }

            // 4. mkdir newFolder + copy non-manifest patch entries into it.
            File newFolder = new File(newFolderPath);
            if (!newFolder.mkdirs() && !newFolder.exists()) {
                throw new CodePushPatchApplyException(
                        "Failed to create new package folder at " + newFolderPath);
            }
            copyTreeExcludingManifest(unzipDir, newFolder);

            // 5. JNI hpatch_by_file: origin bundle + patch -> new bundle.
            File originBundle = new File(currentFolderPath, bundleEntry);
            File newBundle = new File(newFolder, bundleEntry);
            File bundlePatch = new File(newFolder, bundlePatchEntry);
            // hpatch_by_file refuses if the destination already exists.
            //noinspection ResultOfMethodCallIgnored
            newBundle.delete();
            String hpatchErr = applyBundlePatchNative(
                    originBundle.getAbsolutePath(),
                    newBundle.getAbsolutePath(),
                    bundlePatch.getAbsolutePath());
            if (hpatchErr != null) {
                throw new CodePushPatchApplyException(
                        "Bundle patch apply failed: " + hpatchErr);
            }
            // Discard the patch file from newFolder — scaffolding only.
            //noinspection ResultOfMethodCallIgnored
            bundlePatch.delete();

            // 6. Walk manifest copies — copy from origin into new folder.
            JSONArray copies = manifest.optJSONArray("copies");
            if (copies != null) {
                for (int i = 0; i < copies.length(); i++) {
                    JSONObject op = copies.optJSONObject(i);
                    if (op == null) continue;
                    String from = op.optString("from", "");
                    String to = op.optString("to", "");
                    if (from.isEmpty() || to.isEmpty()) continue;
                    File src = new File(currentFolderPath, from);
                    File dst = new File(newFolder, to);
                    if (!src.exists()) {
                        throw new CodePushPatchApplyException(
                                "Copy source missing in origin: " + from);
                    }
                    File parent = dst.getParentFile();
                    if (parent != null && !parent.exists() && !parent.mkdirs()) {
                        throw new CodePushPatchApplyException(
                                "Failed to mkdir parent of " + dst.getAbsolutePath());
                    }
                    try {
                        Files.copy(src.toPath(), dst.toPath(),
                                StandardCopyOption.REPLACE_EXISTING);
                    } catch (IOException e) {
                        throw new CodePushPatchApplyException(
                                "Failed to copy " + from + " -> " + to, e);
                    }
                }
            }

            // 7. Resolve the relative bundle path inside newFolder.
            String relativeBundlePath = CodePushUpdateUtils.findJSBundleInUpdateContents(
                    newFolderPath, expectedBundleFileName);
            if (relativeBundlePath == null) {
                throw new CodePushPatchApplyException(
                        "JS bundle not found in patched folder.");
            }

            // 8. Verify hash + signature (mirrors CodePushUpdateManager:268–294).
            verifyPatchedFolder(newFolderPath, expectedHash, publicKey);

            // 9. Persist app.json with the resolved bundle path baked in —
            //    same call CodePushUpdateManager.downloadPackage makes.
            CodePushUtils.setJSONValueForKey(updatePackage,
                    CodePushConstants.RELATIVE_BUNDLE_PATH_KEY, relativeBundlePath);
            String metadataPath = CodePushUtils.appendPathComponent(
                    newFolderPath, CodePushConstants.PACKAGE_FILE_NAME);
            try {
                CodePushUtils.writeJsonToFile(updatePackage, metadataPath);
            } catch (IOException e) {
                throw new CodePushPatchApplyException("Failed to write app.json.", e);
            }

            succeeded = true;
        } finally {
            FileUtils.deleteDirectoryAtPath(unzipDir.getAbsolutePath());
            if (!succeeded) {
                FileUtils.deleteDirectoryAtPath(newFolderPath);
            }
        }
    }

    // ------------------------------------------------------------------
    // ZIP-extraction safety defenses (mirrors internal/patch's archive.ts
    // and the iOS .mm validateExtractedTree). Pre-flight per-entry checks
    // before writing anything to disk.
    // ------------------------------------------------------------------
    private static void extractZipSafely(String zipPath, File destDir)
            throws CodePushPatchApplyException {
        if (!destDir.mkdirs() && !destDir.exists()) {
            throw new CodePushPatchApplyException(
                    "Failed to create extraction dir: " + destDir);
        }
        Path destRoot;
        try {
            destRoot = destDir.getCanonicalFile().toPath();
        } catch (IOException e) {
            throw new CodePushPatchApplyException(
                    "Failed to canonicalize extraction dir.", e);
        }

        Set<String> seenFileKeys = new HashSet<>();
        Set<String> seenDirKeys = new HashSet<>();

        try (ZipFile zip = new ZipFile(zipPath)) {
            java.util.Enumeration<? extends ZipEntry> entries = zip.entries();
            while (entries.hasMoreElements()) {
                ZipEntry entry = entries.nextElement();
                String name = entry.getName().replace('\\', '/');

                // Skip directory entries; we mkdir on demand below.
                if (name.endsWith("/")) continue;

                if (name.indexOf('\0') >= 0) {
                    throw new CodePushPatchApplyException(
                            "Patch ZIP entry name contains null byte.");
                }
                if (name.startsWith("/") || name.matches("^[A-Za-z]:[\\\\/].*")) {
                    throw new CodePushPatchApplyException(
                            "Patch ZIP entry uses absolute path: " + name);
                }
                String normalized = normalizePosix(name);
                if (normalized.startsWith("..") || normalized.equals(".")
                        || normalized.isEmpty()) {
                    throw new CodePushPatchApplyException(
                            "Patch ZIP entry escapes destination: " + name);
                }

                File outFile = new File(destDir, normalized);
                Path outResolved = outFile.toPath().toAbsolutePath().normalize();
                if (!outResolved.startsWith(destRoot)) {
                    throw new CodePushPatchApplyException(
                            "Patch ZIP entry resolves outside extraction dir: " + name);
                }

                String canonical = Normalizer.normalize(normalized, Normalizer.Form.NFC)
                        .toLowerCase(Locale.ROOT);
                if (seenFileKeys.contains(canonical)) {
                    throw new CodePushPatchApplyException(
                            "Patch ZIP contains duplicate (case/Unicode-folded) entry: " + name);
                }
                if (seenDirKeys.contains(canonical)) {
                    throw new CodePushPatchApplyException(
                            "Patch ZIP entry path is also a directory in another entry: " + name);
                }

                String[] segments = normalized.split("/");
                StringBuilder acc = new StringBuilder();
                for (int i = 0; i < segments.length - 1; i++) {
                    if (i > 0) acc.append('/');
                    acc.append(segments[i]);
                    String ancestor = Normalizer.normalize(acc.toString(),
                            Normalizer.Form.NFC).toLowerCase(Locale.ROOT);
                    if (seenFileKeys.contains(ancestor)) {
                        throw new CodePushPatchApplyException(
                                "Patch ZIP entry's ancestor is a file in another entry: " + name);
                    }
                    seenDirKeys.add(ancestor);
                }
                seenFileKeys.add(canonical);

                File parent = outFile.getParentFile();
                if (parent != null && !parent.exists() && !parent.mkdirs()) {
                    throw new CodePushPatchApplyException(
                            "Failed to mkdir " + parent.getAbsolutePath());
                }

                try (InputStream in = zip.getInputStream(entry);
                     OutputStream out = Files.newOutputStream(outFile.toPath())) {
                    byte[] buf = new byte[16 * 1024];
                    int n;
                    while ((n = in.read(buf)) > 0) {
                        out.write(buf, 0, n);
                    }
                }

                // ZIP doesn't carry symlinks portably, but a hostile entry could
                // arrive as one anyway. Re-check after write.
                if (Files.isSymbolicLink(outFile.toPath())) {
                    throw new CodePushPatchApplyException(
                            "Patch ZIP entry materialized as a symlink: " + name);
                }
            }
        } catch (CodePushPatchApplyException rethrow) {
            throw rethrow;
        } catch (IOException e) {
            throw new CodePushPatchApplyException("Failed to read patch ZIP.", e);
        }
    }

    private static String normalizePosix(String input) {
        Deque<String> stack = new ArrayDeque<>();
        for (String segment : input.split("/")) {
            if (segment.isEmpty() || segment.equals(".")) continue;
            if (segment.equals("..")) {
                if (stack.isEmpty()) return "..";
                stack.pop();
                continue;
            }
            stack.push(segment);
        }
        if (stack.isEmpty()) return ".";
        List<String> rev = new ArrayList<>(stack);
        java.util.Collections.reverse(rev);
        return String.join("/", rev);
    }

    private static void copyTreeExcludingManifest(File src, File dst)
            throws CodePushPatchApplyException {
        if (!src.isDirectory()) return;
        File[] children = src.listFiles();
        if (children == null) return;
        for (File child : children) {
            if (child.getName().equals(MANIFEST_FILE_NAME) && child.getParentFile().equals(src)) {
                continue;
            }
            File target = new File(dst, child.getName());
            try {
                if (child.isDirectory()) {
                    if (!target.mkdirs() && !target.exists()) {
                        throw new CodePushPatchApplyException(
                                "Failed to mkdir " + target.getAbsolutePath());
                    }
                    copyTreeExcludingManifest(child, target);
                } else {
                    Files.copy(child.toPath(), target.toPath(),
                            StandardCopyOption.REPLACE_EXISTING,
                            LinkOption.NOFOLLOW_LINKS);
                }
            } catch (IOException e) {
                throw new CodePushPatchApplyException(
                        "Failed to copy " + child.getAbsolutePath(), e);
            }
        }
    }

    private static void verifyPatchedFolder(String newFolderPath, String expectedHash,
                                            String publicKey)
            throws CodePushPatchApplyException {
        String signaturePath = CodePushUpdateUtils.getSignatureFilePath(newFolderPath);
        boolean signaturePresent = FileUtils.fileAtPathExists(signaturePath);
        boolean publicKeyConfigured = (publicKey != null && !publicKey.isEmpty());

        try {
            if (publicKeyConfigured) {
                if (!signaturePresent) {
                    throw new CodePushPatchApplyException(
                            "Public key configured but no JWT signature inside patched bundle.");
                }
                CodePushUpdateUtils.verifyFolderHash(newFolderPath, expectedHash);
                CodePushUpdateUtils.verifyUpdateSignature(newFolderPath, expectedHash, publicKey);
                return;
            }
            if (signaturePresent) {
                CodePushUtils.log("Warning: JWT signature present in patched bundle but no "
                        + "public key configured; running folder-hash verification only.");
            }
            CodePushUpdateUtils.verifyFolderHash(newFolderPath, expectedHash);
        } catch (CodePushInvalidUpdateException e) {
            throw new CodePushPatchApplyException(e.getMessage(), e);
        }
    }

    private static native String applyBundlePatchNative(
            String originBundlePath, String newBundlePath, String patchFilePath);

    private CodePushHDiffPatchApplier() { }
}
