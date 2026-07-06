"""Cursor Cloud Agents API client."""

import asyncio
import os
import time
from typing import Optional

import httpx

CURSOR_BASE_URL = "https://api.cursor.com"
POLL_INTERVAL_SEC = 2.0
MAX_WAIT_SEC = 180.0

TERMINAL_STATUSES = {"FINISHED", "FAILED", "CANCELLED", "ERROR"}


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

    async def prompt(self, system_prompt: str, user_prompt: str) -> str:
        if not self.api_key:
            raise ValueError("CURSOR_API_KEY is not set")

        full_prompt = f"{system_prompt}\n\n---\n\n{user_prompt}"
        async with httpx.AsyncClient(timeout=60.0) as client:
            if self._agent_id:
                run_id = await self._create_run(client, self._agent_id, full_prompt)
                agent_id = self._agent_id
            else:
                agent_id, run_id = await self._create_agent(client, full_prompt)
                self._agent_id = agent_id

            return await self._wait_for_result(client, agent_id, run_id)

    async def _create_agent(self, client: httpx.AsyncClient, prompt: str) -> tuple[str, str]:
        payload = {
            "prompt": {"text": prompt},
            "model": {"id": self.model},
        }
        response = await client.post(
            f"{CURSOR_BASE_URL}/v1/agents",
            headers=self._headers(),
            json=payload,
        )
        response.raise_for_status()
        data = response.json()
        agent_id = data["agent"]["id"]
        run_id = data["run"]["id"]
        return agent_id, run_id

    async def _create_run(
        self, client: httpx.AsyncClient, agent_id: str, prompt: str
    ) -> str:
        response = await client.post(
            f"{CURSOR_BASE_URL}/v1/agents/{agent_id}/runs",
            headers=self._headers(),
            json={"prompt": {"text": prompt}},
        )
        if response.status_code == 409:
            await asyncio.sleep(POLL_INTERVAL_SEC * 2)
            response = await client.post(
                f"{CURSOR_BASE_URL}/v1/agents/{agent_id}/runs",
                headers=self._headers(),
                json={"prompt": {"text": prompt}},
            )
        response.raise_for_status()
        return response.json()["id"]

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
