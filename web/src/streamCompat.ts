import type { Device } from "./api";

export function isAppleTvDevice(device: Device | null | undefined): boolean {
  const family = device?.capabilities?.chip_family?.toLowerCase() ?? "";
  const note = device?.capabilities?.chip_note?.toLowerCase() ?? "";
  const mfg = device?.manufacturer?.toLowerCase() ?? "";
  return family === "apple" || mfg === "apple" || note.includes("avplayer");
}

/** Fire OS has no Android TV Remote service. Amlogic alone is not enough — onn. boxes pair. */
export function isFireOsDevice(device: Device | null | undefined): boolean {
  if (!device || isAppleTvDevice(device)) return false;
  const mfg = device.manufacturer?.trim().toLowerCase() ?? "";
  if (mfg === "amazon") return true;
  const model = device.model?.trim().toLowerCase() ?? "";
  return model.startsWith("aft");
}
