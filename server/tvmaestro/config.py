"""Persistent config store under TVMAESTRO_DATA_DIR."""

from __future__ import annotations

import json
import logging
import os
import shutil
import tempfile
from pathlib import Path

from .models import AppConfig

logger = logging.getLogger(__name__)

DEFAULT_CONFIG_NAME = "config.json"


def atomic_write_text(path: Path, content: str) -> None:
    """Write text atomically via a same-directory temp file and os.replace."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp_path, path)
    except BaseException:
        tmp_path.unlink(missing_ok=True)
        raise


def data_dir() -> Path:
    raw = os.environ.get("TVMAESTRO_DATA_DIR", "").strip()
    if raw:
        path = Path(raw)
    else:
        # Dev default: <repo>/data (package lives at server/tvmaestro/)
        here = Path(__file__).resolve()
        repo_root = here.parents[2]
        path = repo_root / "data" if (repo_root / "server").is_dir() else Path("./data")
    path.mkdir(parents=True, exist_ok=True)
    return path


def _example_config_path() -> Path | None:
    here = Path(__file__).resolve()
    candidates = [
        here.parents[2] / "config.example.json",  # repo root (local)
        Path("/app/config.example.json"),  # Docker image
        data_dir() / "config.example.json",
    ]
    for path in candidates:
        if path.is_file():
            return path
    return None


class ConfigStore:
    def __init__(self, path: Path | None = None) -> None:
        self.path = path or (data_dir() / DEFAULT_CONFIG_NAME)
        self.config = AppConfig()
        self._load_or_seed()

    def _load_or_seed(self) -> None:
        if not self.path.exists():
            example = _example_config_path()
            if example is not None:
                shutil.copy(example, self.path)
                logger.info("Seeded config from %s", example)
            else:
                self.save()
                return
        try:
            raw = json.loads(self.path.read_text(encoding="utf-8"))
            self.config = AppConfig.model_validate(raw)
        except Exception as exc:  # noqa: BLE001
            logger.warning("Failed to load config (%s); using defaults", exc)
            self.config = AppConfig()
            self.save()

    def save(self) -> None:
        atomic_write_text(
            self.path,
            self.config.model_dump_json(indent=2) + "\n",
        )

    def update(self, **kwargs: object) -> AppConfig:
        data = self.config.model_dump()
        for key, value in kwargs.items():
            if value is not None and key in data:
                data[key] = value
        self.config = AppConfig.model_validate(data)
        self.save()
        return self.config
