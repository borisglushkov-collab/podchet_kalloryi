"""Tests for Cursor client image prompt payload."""

from cursor_client import CursorClient


def test_build_prompt_payload_with_image():
    payload = CursorClient()._build_prompt_payload(
        "analyze food",
        [(b"fake-image", "image/jpeg")],
    )
    assert payload["text"] == "analyze food"
    assert len(payload["images"]) == 1
    assert payload["images"][0]["mimeType"] == "image/jpeg"
    assert payload["images"][0]["data"]


def test_build_prompt_payload_text_only():
    payload = CursorClient()._build_prompt_payload("hello")
    assert payload == {"text": "hello"}
