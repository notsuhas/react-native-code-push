#import "CodePushHDiffPatchApplier.h"
#import "CodePush.h"
#import "CodePushErrorUtils.h"

#if __has_include(<SSZipArchive/SSZipArchive.h>)
#import <SSZipArchive/SSZipArchive.h>
#else
#import "SSZipArchive.h"
#endif

#include <string>
#include <unordered_set>
#include <vector>

#include "patch_core/patch_core.h"

// Constants must mirror CodePushPackage.m's private statics. Keeping them
// duplicated rather than exposing the originals via a header — these are
// stable enough that drift is very unlikely, and the alternative pollutes
// the public CodePush header.
static NSString *const kPatchManifestFileName = @"__diff.json";
static NSString *const kUpdateMetadataFileName = @"app.json";
static NSString *const kRelativeBundlePathKey = @"bundlePath";
static NSString *const kPackageHashKey = @"packageHash";
static NSString *const kErrorDomain = @"CodePushHDiffPatch";

static NSError *MakeError(NSString *message) {
    return [CodePushErrorUtils errorWithMessage:message];
}

@implementation CodePushHDiffPatchApplier

#pragma mark - ZIP-extraction safety defenses

/**
 * Walks `rootDir` recursively, validating every entry against the same
 * defenses the server-side `internal/patch/src/archive.ts` implements:
 *   - real path stays inside `rootDir` (defense-in-depth even though
 *     SSZipArchive 2.5+ blocks Zip Slip during extraction)
 *   - no symbolic links anywhere in the tree
 *   - no collisions on the canonical (NFC + lowercase) path key, which
 *     would alias on iOS HFS+ and silently overwrite each other
 */
+ (BOOL)validateExtractedTree:(NSString *)rootDir
                        error:(NSError **)error
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *rootURL = [[NSURL fileURLWithPath:rootDir] URLByResolvingSymlinksInPath];
    NSString *rootResolved = [[rootURL path] stringByStandardizingPath];

    NSDirectoryEnumerator<NSURL *> *enumerator =
        [fm enumeratorAtURL:[NSURL fileURLWithPath:rootDir]
            includingPropertiesForKeys:@[NSURLIsSymbolicLinkKey, NSURLIsDirectoryKey]
                               options:0
                          errorHandler:nil];

    std::unordered_set<std::string> seenFileKeys;
    std::unordered_set<std::string> seenDirKeys;

    for (NSURL *url in enumerator) {
        NSNumber *isSymlink = nil;
        [url getResourceValue:&isSymlink forKey:NSURLIsSymbolicLinkKey error:nil];
        if (isSymlink.boolValue) {
            if (error) *error = MakeError([NSString stringWithFormat:
                @"Patch ZIP contained a symlink entry (%@); refusing to apply.", url.path]);
            return NO;
        }

        NSString *resolved = [[url URLByResolvingSymlinksInPath].path stringByStandardizingPath];
        if (![resolved hasPrefix:[rootResolved stringByAppendingString:@"/"]] && ![resolved isEqualToString:rootResolved]) {
            if (error) *error = MakeError([NSString stringWithFormat:
                @"Patch ZIP entry resolves outside the extraction directory (%@).", url.path]);
            return NO;
        }

        NSNumber *isDir = nil;
        [url getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
        if (isDir.boolValue) continue;

        // Canonical key: relative path under root, NFC-normalized + lowercased.
        NSString *relative = [resolved substringFromIndex:rootResolved.length + 1];
        NSString *canonical = [[relative precomposedStringWithCanonicalMapping] lowercaseString];
        std::string key = canonical.UTF8String;

        if (seenFileKeys.count(key)) {
            if (error) *error = MakeError([NSString stringWithFormat:
                @"Patch ZIP contains duplicate (case/Unicode-folded) entry path: %@", relative]);
            return NO;
        }
        if (seenDirKeys.count(key)) {
            if (error) *error = MakeError([NSString stringWithFormat:
                @"Patch ZIP entry path is also a directory in another entry: %@", relative]);
            return NO;
        }

        // Track parent dirs so a future entry that reuses one as a file fails
        NSArray<NSString *> *segments = [relative pathComponents];
        NSMutableString *acc = [NSMutableString string];
        for (NSUInteger i = 0; i + 1 < segments.count; i++) {
            if (i > 0) [acc appendString:@"/"];
            [acc appendString:segments[i]];
            NSString *ancestorCanonical = [[acc precomposedStringWithCanonicalMapping] lowercaseString];
            std::string ancestorKey = ancestorCanonical.UTF8String;
            if (seenFileKeys.count(ancestorKey)) {
                if (error) *error = MakeError([NSString stringWithFormat:
                    @"Patch ZIP entry's ancestor path is a file in another entry: %@", relative]);
                return NO;
            }
            seenDirKeys.insert(ancestorKey);
        }

        seenFileKeys.insert(key);
    }

    return YES;
}

#pragma mark - C++ patch_core boundary

+ (BOOL)runPatchCoreWithManifest:(NSDictionary *)manifestDict
                   currentFolder:(NSString *)currentFolder
                       newFolder:(NSString *)newFolder
                     bundleEntry:(NSString *)bundleEntry
                bundlePatchEntry:(NSString *)bundlePatchEntry
                           error:(NSError **)error
{
    pushy::patch::PatchManifest manifest;

    NSArray *copies = manifestDict[@"copies"];
    if ([copies isKindOfClass:[NSArray class]]) {
        for (id raw in copies) {
            if (![raw isKindOfClass:[NSDictionary class]]) continue;
            NSString *from = raw[@"from"];
            NSString *to = raw[@"to"];
            if (from.length == 0 || to.length == 0) continue;
            pushy::patch::CopyOperation op;
            op.from = from.UTF8String;
            op.to = to.UTF8String;
            manifest.copies.push_back(std::move(op));
        }
    }
    NSArray *deletes = manifestDict[@"deletes"];
    if ([deletes isKindOfClass:[NSArray class]]) {
        for (id raw in deletes) {
            if ([raw isKindOfClass:[NSString class]]) {
                manifest.deletes.push_back(((NSString *)raw).UTF8String);
            }
        }
    }

    pushy::patch::FileSourcePatchOptions opts;
    opts.manifest = std::move(manifest);
    opts.source_root = currentFolder.UTF8String;
    opts.target_root = newFolder.UTF8String;
    opts.origin_bundle_path =
        [[currentFolder stringByAppendingPathComponent:bundleEntry] UTF8String];
    opts.bundle_patch_path =
        [[newFolder stringByAppendingPathComponent:bundlePatchEntry] UTF8String];
    opts.bundle_output_path =
        [[newFolder stringByAppendingPathComponent:bundleEntry] UTF8String];
    opts.merge_source_subdir = "";
    opts.enable_merge = true;

    pushy::patch::Status status;
    try {
        status = pushy::patch::ApplyPatchFromFileSource(opts);
    } catch (const std::exception &ex) {
        if (error) *error = MakeError([NSString stringWithFormat:
            @"patch_core threw: %s", ex.what()]);
        return NO;
    } catch (...) {
        if (error) *error = MakeError(@"patch_core threw an unknown exception");
        return NO;
    }

    if (!status.ok) {
        if (error) *error = MakeError([NSString stringWithFormat:
            @"patch_core failed: %s", status.message.c_str()]);
        return NO;
    }
    return YES;
}

#pragma mark - Hash + signature verification (parity with downloadPackage)

+ (BOOL)verifyPatchedFolder:(NSString *)newFolder
               expectedHash:(NSString *)expectedHash
                  publicKey:(NSString *)publicKey
                      error:(NSError **)error
{
    NSString *signaturePath = [CodePushUpdateUtils getSignatureFilePath:newFolder];
    BOOL signaturePresent = [[NSFileManager defaultManager] fileExistsAtPath:signaturePath];
    BOOL pubKeyConfigured = (publicKey.length > 0);

    if (pubKeyConfigured) {
        if (!signaturePresent) {
            if (error) *error = MakeError(
                @"Public key configured but no JWT signature inside patched bundle.");
            return NO;
        }
        NSError *hashErr = nil;
        if (![CodePushUpdateUtils verifyFolderHash:newFolder
                                      expectedHash:expectedHash
                                             error:&hashErr]) {
            if (error) *error = hashErr ?: MakeError(@"Patched bundle failed folder-hash check.");
            return NO;
        }
        NSError *sigErr = nil;
        if (![CodePushUpdateUtils verifyUpdateSignatureFor:newFolder
                                              expectedHash:expectedHash
                                             withPublicKey:publicKey
                                                     error:&sigErr]) {
            if (error) *error = sigErr ?: MakeError(@"Patched bundle failed code-signing check.");
            return NO;
        }
        return YES;
    }

    // No public key configured. Match downloadPackage's behavior: if a sig
    // exists in the bundle but no key, log a warning and verify hash anyway.
    if (signaturePresent) {
        CPLog(@"Warning: JWT signature present in patched bundle but no public "
              "key configured; running folder-hash verification only.");
    }

    NSError *hashErr = nil;
    if (![CodePushUpdateUtils verifyFolderHash:newFolder
                                  expectedHash:expectedHash
                                         error:&hashErr]) {
        if (error) *error = hashErr ?: MakeError(@"Patched bundle failed folder-hash check.");
        return NO;
    }
    return YES;
}

#pragma mark - Public entry point

+ (BOOL)applyPatchWithPackage:(NSMutableDictionary *)updatePackage
                 patchZipPath:(NSString *)patchZipPath
           currentPackagePath:(NSString *)currentFolder
               newPackagePath:(NSString *)newFolder
                     baseHash:(NSString *)baseHash
                    publicKey:(NSString *)publicKey
                        error:(NSError **)error
{
    NSString *expectedHash = updatePackage[kPackageHashKey];
    if (expectedHash.length == 0) {
        if (error) *error = MakeError(@"Update package is missing packageHash.");
        return NO;
    }
    if (currentFolder.length == 0 || patchZipPath.length == 0 || newFolder.length == 0) {
        if (error) *error = MakeError(@"Missing currentFolder / patchZipPath / newFolder.");
        return NO;
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:currentFolder]) {
        if (error) *error = MakeError(@"Current package folder does not exist; cannot patch.");
        return NO;
    }

    BOOL succeeded = NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *patchUnzipDir = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[@"codepush-patch-"
            stringByAppendingString:[[NSUUID UUID] UUIDString]]];

    @try {
        // 1. Unzip the patch into a jailed tmp dir.
        NSError *unzipErr = nil;
        if (![SSZipArchive unzipFileAtPath:patchZipPath
                             toDestination:patchUnzipDir
                                 overwrite:YES
                                  password:nil
                                     error:&unzipErr]) {
            if (error) *error = unzipErr ?: MakeError(@"Failed to unzip patch ZIP.");
            return NO;
        }

        // 2. Pre-flight defenses: Zip Slip / symlinks / collisions.
        if (![self validateExtractedTree:patchUnzipDir error:error]) {
            return NO;
        }

        // 3. Read __diff.json.
        NSString *manifestPath = [patchUnzipDir stringByAppendingPathComponent:kPatchManifestFileName];
        NSData *manifestData = [NSData dataWithContentsOfFile:manifestPath];
        if (!manifestData) {
            if (error) *error = MakeError(@"Patch ZIP missing __diff.json.");
            return NO;
        }
        NSError *jsonErr = nil;
        NSDictionary *manifestDict = [NSJSONSerialization JSONObjectWithData:manifestData
                                                                     options:0
                                                                       error:&jsonErr];
        if (![manifestDict isKindOfClass:[NSDictionary class]]) {
            if (error) *error = jsonErr ?: MakeError(@"Patch __diff.json is malformed.");
            return NO;
        }

        // 4. Sanity-check hashes + required fields.
        NSString *fromHash = manifestDict[@"fromPackageHash"];
        NSString *toHash = manifestDict[@"toPackageHash"];
        NSString *bundleEntry = manifestDict[@"bundleEntry"];
        NSString *bundlePatchEntry = manifestDict[@"bundlePatchEntry"];
        if (![fromHash isEqualToString:baseHash]) {
            if (error) *error = MakeError(
                @"Patch fromPackageHash does not match the installed package hash.");
            return NO;
        }
        if (![toHash isEqualToString:expectedHash]) {
            if (error) *error = MakeError(
                @"Patch toPackageHash does not match the expected target hash.");
            return NO;
        }
        if (bundleEntry.length == 0 || bundlePatchEntry.length == 0) {
            if (error) *error = MakeError(
                @"Patch manifest missing bundleEntry or bundlePatchEntry.");
            return NO;
        }

        // 5. Move/copy patch contents into newFolder. patch_core resolves the
        //    bundle output, copies from origin, and merges the rest of source
        //    into target, so newFolder needs the new asset bytes (everything
        //    EXCEPT the manifest itself) before we hand off.
        NSError *mkdirErr = nil;
        if (![fm createDirectoryAtPath:newFolder
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:&mkdirErr]) {
            if (error) *error = mkdirErr;
            return NO;
        }

        NSDirectoryEnumerator *patchEnum = [fm enumeratorAtPath:patchUnzipDir];
        for (NSString *relative in patchEnum) {
            if ([relative isEqualToString:kPatchManifestFileName]) continue;
            NSString *src = [patchUnzipDir stringByAppendingPathComponent:relative];
            NSString *dst = [newFolder stringByAppendingPathComponent:relative];
            BOOL isDir = NO;
            if (![fm fileExistsAtPath:src isDirectory:&isDir] || isDir) continue;
            NSError *parentErr = nil;
            [fm createDirectoryAtPath:[dst stringByDeletingLastPathComponent]
          withIntermediateDirectories:YES
                           attributes:nil
                                error:&parentErr];
            NSError *copyErr = nil;
            if (![fm copyItemAtPath:src toPath:dst error:&copyErr]) {
                if (error) *error = copyErr;
                return NO;
            }
        }

        // 6. Cross language boundary: apply bundle patch + copies + merge.
        if (![self runPatchCoreWithManifest:manifestDict
                              currentFolder:currentFolder
                                  newFolder:newFolder
                                bundleEntry:bundleEntry
                           bundlePatchEntry:bundlePatchEntry
                                      error:error]) {
            return NO;
        }

        // 7. Discard the bundle-patch file from newFolder; it was scaffolding.
        [fm removeItemAtPath:[newFolder stringByAppendingPathComponent:bundlePatchEntry]
                       error:nil];

        // 8. Resolve the relative bundle path inside newFolder.
        NSError *bundleErr = nil;
        NSString *expectedBundleFileName = [bundleEntry lastPathComponent];
        NSString *relativeBundlePath = [CodePushUpdateUtils
            findMainBundleInFolder:newFolder
                  expectedFileName:expectedBundleFileName
                             error:&bundleErr];
        if (!relativeBundlePath) {
            if (error) *error = bundleErr ?: MakeError(
                @"JS bundle not found in patched folder.");
            return NO;
        }
        updatePackage[kRelativeBundlePathKey] = relativeBundlePath;

        // 9. Verify hash + signature (parity with downloadPackage).
        if (![self verifyPatchedFolder:newFolder
                          expectedHash:expectedHash
                             publicKey:publicKey
                                 error:error]) {
            return NO;
        }

        // 10. Persist app.json — same call CodePushPackage.downloadPackage makes.
        NSString *metadataPath =
            [newFolder stringByAppendingPathComponent:kUpdateMetadataFileName];
        NSError *serializeErr = nil;
        NSData *metadataData = [NSJSONSerialization dataWithJSONObject:updatePackage
                                                               options:0
                                                                 error:&serializeErr];
        if (!metadataData) {
            if (error) *error = serializeErr ?: MakeError(@"Failed to serialize update package.");
            return NO;
        }
        NSError *writeErr = nil;
        if (![metadataData writeToFile:metadataPath options:NSDataWritingAtomic error:&writeErr]) {
            if (error) *error = writeErr ?: MakeError(@"Failed to write app.json.");
            return NO;
        }

        succeeded = YES;
        return YES;
    } @finally {
        // Clean up tmp unzip dir always; clean up newFolder on failure so the
        // caller's hash-keyed slot is empty for the full-bundle fallback.
        [fm removeItemAtPath:patchUnzipDir error:nil];
        if (!succeeded) {
            [fm removeItemAtPath:newFolder error:nil];
        }
    }
}

@end
