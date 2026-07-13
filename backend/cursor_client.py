"""Cursor Cloud Agents API client."""

import asyncio
import base64
import os
import time
from typing import Optional

import httpx

CURSOR_BASE_URL = "https://api.cursor.com"
POLL_INTERVAL_SEC = 2.0
MAX_WAIT_SEC = 180.0

TERMINAL_STATUSES = {"FINISHED", "FAILED", "CANCELLED", "ERROR"}

_SUPPORTED_IMAGE_MIME = {
    "image/png",
    "image/jpeg",
    "image/jpg",
    "image/gif",
    "image/webp",
}


class CursorClient:
    def __init__(self, api_key: Optional[str] = None, model: Optional[str] = None):
        self.api_key = api_key or os.getenv("CURSOR_API_KEY", "")
        self.model = model or os.getenv("CURSOR_MODEL", "composer-2.5")
        self._agent_id: Optional[str] = None

    def _headers(self) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }

    @staticmethod
    def _normalize_mime(mime_type: str) -> str:
        mime = (mime_type or "image/jpeg").lower()
        if mime == "image/jpg":
            return "image/jpeg"
        if mime in _SUPPORTED_IMAGE_MIME:
            return mime
        return "image/jpeg"

    def _build_prompt_payload(
        self,
        text: str,
        images: list[tuple[bytes, str]] | None = None,
    ) -> dict:
        payload: dict = {"text": text}
        if not images:
            return payload
        image_entries = []
        for image_bytes, mime_type in images[:5]:
            image_entries.append(
                {
                    "data": base64.b64encode(image_bytes).decode("ascii"),
                    "mimeType": self._normalize_mime(mime_type),
                }
            )
        if image_entries:
            payload["images"] = image_entries
        return payload

    async def prompt(self, system_prompt: str, user_prompt: str) -> str:
        if not self.api_key:
            raise ValueError("CURSOR_API_KEY is not set")

        full_prompt = f"{system_prompt}\n\n---\n\n{user_prompt}"
        return await self._run_prompt(self._build_prompt_payload(full_prompt))

    async def prompt_with_images(
        self,
        system_prompt: str,
        user_prompt: str,
        images: list[tuple[bytes, str]],
    ) -> str:
        if not self.api_key:
            raise ValueError("CURSOR_API_KEY is not set")
        if not images:
            raise ValueError("At least one image is required")

        full_prompt = f"{system_prompt}\n\n---\n\n{user_prompt}"
        return await self._run_prompt(self._build_prompt_payload(full_prompt, images))

    async def _run_prompt(self, prompt_payload: dict) -> str:
        async with httpx.AsyncClient(timeout=60.0) as client:
            if self._agent_id:
                try:
                    run_id = await self._create_run(client, self._agent_id, prompt_payload)
                except httpx.HTTPStatusError as exc:
                    if exc.response.status_code in {404, 410}:
                        self._agent_id = None
                        agent_id, run_id = await self._create_agent(client, prompt_payload)
                        self._agent_id = agent_id
                    elif exc.response.status_code == 409:
                        await self._cancel_active_run(client, self._agent_id)
                        run_id = await self._create_run(client, self._agent_id, prompt_payload)
                    else:
                        raise
            else:
                agent_id, run_id = await self._create_agent(client, prompt_payload)
                self._agent_id = agent_id

            return await self._wait_for_result(client, self._agent_id, run_id)

    async def _create_agent(
        self, client: httpx.AsyncClient, prompt_payload: dict
    ) -> tuple[str, str]:
        payload = {
            "prompt": prompt_payload,
            "model": {"id": self.model},
        }
        response = await client.post(
            f"{CURSOR_BASE_URL}/v1/agents",
            headers=self._headers(),
            json=payload,
        )
        if response.status_code == 400:
            detail = self._error_detail(response)
            if "limit" in detail.lower() or "upgrade" in detail.lower():
                agent_id = await self._reuse_existing_agent(client)
                if agent_id:
                    self._agent_id = agent_id
                    run_id = await self._create_run(client, agent_id, prompt_payload)
                    return agent_id, run_id
        response.raise_for_status()
        data = response.json()
        agent_id = data["agent"]["id"]
        run_id = self._parse_run_id(data)
        return agent_id, run_id

    def _parse_run_id(self, data: dict) -> str:
        run = data.get("run")
        if isinstance(run, dict) and run.get("id"):
            return str(run["id"])
        if data.get("id"):
            return str(data["id"])
        raise RuntimeError(f"Cursor API: run id not found in response: {data}")

    async def _create_run(
        self, client: httpx.AsyncClient, agent_id: str, prompt_payload: dict
    ) -> str:
        for attempt in range(5):
            response = await client.post(
                f"{CURSOR_BASE_URL}/v1/agents/{agent_id}/runs",
                headers=self._headers(),
                json={"prompt": prompt_payload},
            )
            if response.status_code == 409:
                await self._cancel_active_run(client, agent_id)
                await asyncio.sleep(POLL_INTERVAL_SEC * (attempt + 2))
                continue
            response.raise_for_status()
            return self._parse_run_id(response.json())
        # Последняя попытка — новый агент
        self._agent_id = None
        new_agent_id, run_id = await self._create_agent(client, prompt_payload)
        self._agent_id = new_agent_id
        return run_id

    async def _cancel_active_run(self, client: httpx.AsyncClient, agent_id: str) -> None:
        response = await client.get(
            f"{CURSOR_BASE_URL}/v1/agents/{agent_id}",
            headers=self._headers(),
        )
        if response.status_code != 200:
            return
        latest_run_id = response.json().get("latestRunId")
        if not latest_run_id:
            return
        await client.post(
            f"{CURSOR_BASE_URL}/v1/agents/{agent_id}/runs/{latest_run_id}/cancel",
            headers=self._headers(),
        )

    async def _reuse_existing_agent(self, client: httpx.AsyncClient) -> Optional[str]:
        response = await client.get(
            f"{CURSOR_BASE_URL}/v1/agents?limit=20",
            headers=self._headers(),
        )
        if response.status_code != 200:
            return None
        items = response.json().get("items", [])
        if not items:
            return None
        return str(items[0]["id"])

    def _error_detail(self, response: httpx.Response) -> str:
        try:
            data = response.json()
            error = data.get("error", data)
            if isinstance(error, dict):
                return str(error.get("message", error))
            return str(error)
        except Exception:
            return response.text

    async def _wait_for_result(
        self, client: httpx.AsyncClient, agent_id: str, run_id: str
    ) -> str:
        deadline = time.monotonic() + MAX_WAIT_SEC
        while time.monotonic() < deadline:
            response = await client.get(
                f"{CURSOR_BASE_URL}/v1/agents/{agent_id}/runs/{run_id}",
                headers=self._headers(),
            )
            response.raise_for_status()
            data = response.json()
            status = data.get("status", "")
            if status in TERMINAL_STATUSES:
                if status != "FINISHED":
                    raise RuntimeError(f"Cursor run failed with status: {status}")
                result = data.get("result", "")
                if not result:
                    raise RuntimeError("Cursor run finished without result text")
                return result
            await asyncio.sleep(POLL_INTERVAL_SEC)
        raise TimeoutError("Cursor API request timed out")

    def reset_session(self) -> None:
        self._agent_id = None
