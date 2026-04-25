#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Applies an HDiffPatch ZIP produced by the rnota worker to a previous
 * CodePush release folder, producing a fully-formed new release folder.
 *
 * This is the iOS counterpart to react-native-update's archive-patch core,
 * specialized for CodePush:
 *   - parses the patch ZIP's `__diff.json` manifest
 *   - applies the bundle's binary diff via patch_core (HDiffPatch)
 *   - walks the manifest's copies / merge paths via patch_core
 *   - copies any newly-added asset bytes from the patch ZIP into the new folder
 *   - mirrors `CodePushPackage.downloadPackage`'s integrity check (hash +
 *     optional JWT signature) and metadata persistence (`app.json`)
 *
 * Failure cleans up the new folder and returns an `NSError` so the JS layer
 * can fall back to the full-bundle download path.
 */
@interface CodePushHDiffPatchApplier : NSObject

+ (BOOL)applyPatchWithPackage:(NSMutableDictionary *)updatePackage
                 patchZipPath:(NSString *)patchZipPath
           currentPackagePath:(NSString *)currentFolder
               newPackagePath:(NSString *)newFolder
                     baseHash:(NSString *)baseHash
                    publicKey:(nullable NSString *)publicKey
                        error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
