import assert from "node:assert/strict";
import test from "node:test";

import { totalReleaseDownloads } from "./downloads.js";

test("counts installer assets across GitHub releases", () => {
  const releases = [
    { assets: [
      { name: "BetterTot-0.3.1.pkg", download_count: 3 },
      { name: "BetterTot-0.3.1.zip", download_count: 2 },
      { name: "checksums.txt", download_count: 50 },
    ] },
    { assets: [{ name: "BetterTot-0.3.0.PKG", download_count: 4 }] },
  ];

  assert.equal(totalReleaseDownloads(releases), 9);
});

test("rejects malformed GitHub release data", () => {
  assert.throws(
    () => totalReleaseDownloads([{ assets: [{ name: "BetterTot.pkg", download_count: -1 }] }]),
    /Invalid GitHub release data/
  );
});
