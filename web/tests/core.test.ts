import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { isAppleTvDevice, isFireOsDevice } from "../src/streamCompat.ts";
import {
  SAMPLE_CHANNELS,
  SAMPLE_DEVICES,
  sampleProgrammes,
  sampleStatus,
} from "../src/sampleData.ts";

describe("streamCompat", () => {
  it("identifies Apple TV devices by chip family, manufacturer, or note", () => {
    assert.equal(
      isAppleTvDevice({
        id: "1",
        name: "Living Room",
        host: "10.0.0.5",
        port: 6791,
        online: true,
        capabilities: {
          multiview_max: 9,
          layouts: ["1", "2x2", "3x3"],
          cec: { power: true, volume: true, mute: true, method: "appletv_companion" },
          mpeg_ts: true,
          hls: true,
          chip_family: "apple",
        },
      }),
      true,
    );
    assert.equal(
      isAppleTvDevice({
        id: "2",
        name: "Shield",
        host: "10.0.0.6",
        port: 6791,
        online: true,
        manufacturer: "NVIDIA",
        capabilities: {
          multiview_max: 4,
          layouts: ["1", "2x2"],
          cec: { power: true, volume: true, mute: true, method: "androidtv_remote" },
          mpeg_ts: true,
          hls: true,
          chip_family: "nvidia_tegra",
        },
      }),
      false,
    );
  });

  it("identifies Fire OS devices without misclassifying Apple TV or onn boxes", () => {
    assert.equal(
      isFireOsDevice({
        id: "3",
        name: "Fire Stick",
        host: "10.0.0.7",
        port: 6791,
        online: true,
        manufacturer: "Amazon",
        model: "AFTMM",
        capabilities: {
          multiview_max: 1,
          layouts: ["1"],
          cec: { power: false, volume: true, mute: true, method: "keys" },
          mpeg_ts: true,
          hls: true,
          chip_family: "amlogic",
        },
      }),
      true,
    );
    assert.equal(
      isFireOsDevice({
        id: "4",
        name: "onn 4K",
        host: "10.0.0.8",
        port: 6791,
        online: true,
        manufacturer: "onn.",
        model: "4K Streaming Box",
        capabilities: {
          multiview_max: 1,
          layouts: ["1"],
          cec: { power: false, volume: true, mute: true, method: "keys" },
          mpeg_ts: true,
          hls: true,
          chip_family: "amlogic",
        },
      }),
      false,
    );
  });
});

describe("sampleData", () => {
  it("produces non-empty sample programmes covering the requested window", () => {
    const start = 1_700_000_000;
    const end = start + 6 * 3600;
    const programmes = sampleProgrammes(start, end);
    assert.ok(programmes.length > 0);
    for (const p of programmes) {
      assert.ok(p.stop > start && p.start < end);
    }
    const status = sampleStatus();
    assert.equal(status.channels, SAMPLE_CHANNELS.length);
    assert.equal(status.devices_total, SAMPLE_DEVICES.length);
  });
});
