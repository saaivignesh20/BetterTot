export function totalReleaseDownloads(releases) {
  if (!Array.isArray(releases)) throw new Error("Invalid GitHub release data");

  return releases
    .flatMap((release) => {
      if (!release || !Array.isArray(release.assets)) {
        throw new Error("Invalid GitHub release data");
      }
      return release.assets;
    })
    .filter((asset) => typeof asset?.name === "string" && /\.(pkg|zip)$/i.test(asset.name))
    .reduce((total, asset) => {
      if (!Number.isSafeInteger(asset.download_count) || asset.download_count < 0) {
        throw new Error("Invalid GitHub release data");
      }
      const nextTotal = total + asset.download_count;
      if (!Number.isSafeInteger(nextTotal)) throw new Error("Invalid GitHub release data");
      return nextTotal;
    }, 0);
}
