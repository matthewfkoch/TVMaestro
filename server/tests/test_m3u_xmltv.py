from tvmaestro.m3u import parse_m3u
from tvmaestro.xmltv import parse_xmltv, parse_xmltv_time


SAMPLE_M3U = """
#EXTM3U
#EXTINF:-1 tvg-id="espn.us" tvg-chno="206" tvg-logo="http://example/espn.png" group-title="Sports" tvc-guide-stationid="12345",ESPN
http://dvr.example/devices/ANY/channels/206/stream.ts?codec=copy
#EXTINF:-1 tvg-chno="5",Local 5
http://dvr.example/devices/ANY/channels/5/stream.ts
"""

SAMPLE_XMLTV = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE tv SYSTEM "xmltv.dtd">
<tv>
  <channel id="espn.us"><display-name>ESPN</display-name></channel>
  <programme start="20240714180000 +0000" stop="20240714190000 +0000" channel="espn.us">
    <title>SportsCenter</title>
    <sub-title>Evening</sub-title>
    <desc>Highlights</desc>
    <category>Sports</category>
  </programme>
</tv>
"""


def test_parse_m3u():
    channels = parse_m3u(SAMPLE_M3U)
    assert len(channels) == 2
    assert channels[0].name == "ESPN"
    assert channels[0].number == "206"
    assert channels[0].station_id == "12345"
    assert "stream.ts" in channels[0].url


def test_parse_xmltv_time():
    ts = parse_xmltv_time("20240714180000 +0000")
    assert ts == 1720980000


def test_parse_xmltv():
    names, programmes = parse_xmltv(SAMPLE_XMLTV)
    assert names["espn.us"] == "ESPN"
    assert len(programmes) == 1
    assert programmes[0].title == "SportsCenter"
    assert programmes[0].stop > programmes[0].start
