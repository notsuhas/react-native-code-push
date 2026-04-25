import { NativeEventEmitter } from "react-native";
import log from "./logging";

// This function is used to augment remote and local
// package objects with additional functionality/properties
// beyond what is included in the metadata sent by the server.
module.exports = (NativeCodePush) => {
  const remote = (reportStatusDownload) => {
    return {
      async download(downloadProgressCallback) {
        if (!this.downloadUrl) {
          throw new Error("Cannot download an update without a download url");
        }

        let downloadProgressSubscription;
        if (downloadProgressCallback) {
          const codePushEventEmitter = new NativeEventEmitter(NativeCodePush);
          // Use event subscription to obtain download progress.
          downloadProgressSubscription = codePushEventEmitter.addListener(
            "CodePushDownloadProgress",
            downloadProgressCallback
          );
        }

        // Use the downloaded package info. Native code will save the package info
        // so that the client knows what the current package version is.
        try {
          // Hoisted ONCE so both the patch path and the full-bundle fallback
          // see the same prepared package.
          const updatePackageCopy = Object.assign({}, this);
          Object.keys(updatePackageCopy).forEach((key) => (typeof updatePackageCopy[key] === 'function') && delete updatePackageCopy[key]);

          const reportStatusOnce = () => {
            if (reportStatusDownload) {
              reportStatusDownload(this)
              .catch((err) => {
                log(`Report download status failed: ${err}`);
              });
            }
          };

          // Prefer the patch path when the server supplied one. Any failure
          // (download, apply, hash mismatch, signature verify) falls through
          // to the full-bundle download below.
          if (this.patchUrl && this.patchPackageHash) {
            try {
              const patchFilePath = await NativeCodePush.downloadPatchFile(
                this.patchUrl, !!downloadProgressCallback);
              const installedPackage = await NativeCodePush.applyPatchUpdate(
                updatePackageCopy, patchFilePath, this.patchPackageHash);
              reportStatusOnce();
              return { ...installedPackage, ...local };
            } catch (patchErr) {
              log(`Patch apply failed (${patchErr && patchErr.message}); falling back to full bundle.`);
              // intentionally fall through with the same updatePackageCopy
            }
          }

          const downloadedPackage = await NativeCodePush.downloadUpdate(updatePackageCopy, !!downloadProgressCallback);
          reportStatusOnce();
          return { ...downloadedPackage, ...local };
        } finally {
          downloadProgressSubscription && downloadProgressSubscription.remove();
        }
      },

      isPending: false // A remote package could never be in a pending state
    };
  };

  const local = {
    async install(installMode = NativeCodePush.codePushInstallModeOnNextRestart, minimumBackgroundDuration = 0, updateInstalledCallback) {
      const localPackage = this;
      const localPackageCopy = Object.assign({}, localPackage); // In dev mode, React Native deep freezes any object queued over the bridge
      await NativeCodePush.installUpdate(localPackageCopy, installMode, minimumBackgroundDuration);
      updateInstalledCallback && updateInstalledCallback();
      if (installMode == NativeCodePush.codePushInstallModeImmediate) {
        NativeCodePush.restartApp(false);
      } else {
        NativeCodePush.clearPendingRestart();
        localPackage.isPending = true; // Mark the package as pending since it hasn't been applied yet
      }
    },

    isPending: false // A local package wouldn't be pending until it was installed
  };

  return { local, remote };
};