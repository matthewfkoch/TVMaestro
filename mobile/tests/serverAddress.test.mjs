import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { cleanAddress, isLocalHostname, parseServer } = require("../www/serverAddress.js");

describe("companion serverAddress", () => {
  it("strips iOS invisible marks and normalizes fullwidth characters", () => {
    assert.equal(cleanAddress("\u200E192\u3002168\u30021\u300220\u200B"), "192.168.1.20");
    assert.equal(cleanAddress("１９２．１６８．１．５"), "192.168.1.5");
  });

  it("classifies local vs external hostnames", () => {
    for (const h of ["localhost", "tv.local", "127.0.0.1", "10.0.0.4", "192.168.1.2", "172.16.0.1", "172.31.9.9", "[::1]", "fd12::1"]) {
      assert.equal(isLocalHostname(h), true, `expected local: ${h}`);
    }
    for (const h of ["example.com", "172.15.0.1", "172.32.0.1", "8.8.8.8", ""]) {
      assert.equal(isLocalHostname(h), false, `expected non-local: ${h}`);
    }
  });

  it("parses LAN IP with default and custom ports", () => {
    assert.deepEqual(parseServer("192.168.1.20", ""), {
      host: "192.168.1.20",
      port: "6790",
      scheme: "http",
      origin: "http://192.168.1.20:6790",
    });
    assert.deepEqual(parseServer("192.168.1.20:8080", "6790"), {
      host: "192.168.1.20",
      port: "8080",
      scheme: "http",
      origin: "http://192.168.1.20:8080",
    });
  });

  it("requires https for non-local hosts and validates port bounds", () => {
    assert.throws(() => parseServer("tv.example.com", "6790"), /Use https/);
    assert.deepEqual(parseServer("https://tv.example.com", "443"), {
      host: "tv.example.com",
      port: "443",
      scheme: "https",
      origin: "https://tv.example.com:443",
    });
    assert.throws(() => parseServer("192.168.1.20", "70000"), /Port must be/);
    assert.throws(() => parseServer("", "6790"), /Enter the server address/);
  });
});
