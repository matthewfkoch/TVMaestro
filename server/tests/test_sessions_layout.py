from tvmaestro.models import Layout, SessionSlot
from tvmaestro.sessions import LAYOUT_CAPACITY, _with_single_audio


def test_layout_capacity():
    assert LAYOUT_CAPACITY[Layout.one] == 1
    assert LAYOUT_CAPACITY[Layout.two_h] == 2
    assert LAYOUT_CAPACITY[Layout.two_v] == 2
    assert LAYOUT_CAPACITY[Layout.quad] == 4


def test_with_single_audio_skips_empty_panes():
    slots = [
        SessionSlot(channel_id=None, audio=True),
        SessionSlot(channel_id="espn", audio=False),
        SessionSlot(channel_id=None, audio=False),
        SessionSlot(channel_id="cnn", audio=True),
    ]
    fixed = _with_single_audio(slots)
    assert [s.audio for s in fixed] == [False, False, False, True]
