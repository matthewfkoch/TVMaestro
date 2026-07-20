from pathlib import Path

from tvmaestro.main import WEB_DIR, _safe_web_path


def test_safe_web_path_rejects_traversal(tmp_path, monkeypatch):
    web = tmp_path / "web"
    web.mkdir()
    (web / "logo.svg").write_text("<svg/>", encoding="utf-8")
    monkeypatch.setattr("tvmaestro.main.WEB_DIR", web)

    assert _safe_web_path("logo.svg") == (web / "logo.svg").resolve()
    assert _safe_web_path("../secrets.txt") is None
    assert _safe_web_path("..") is None
    assert _safe_web_path("/etc/passwd") is None
    assert _safe_web_path("") is None


def test_safe_web_path_allows_nested_under_web(tmp_path, monkeypatch):
    web = tmp_path / "web"
    nested = web / "assets"
    nested.mkdir(parents=True)
    target = nested / "app.js"
    target.write_text("ok", encoding="utf-8")
    monkeypatch.setattr("tvmaestro.main.WEB_DIR", web)

    assert _safe_web_path("assets/app.js") == target.resolve()
    # Ensure WEB_DIR constant remains a Path for production import
    assert isinstance(WEB_DIR, Path)
