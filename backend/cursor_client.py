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
                try:
                    run_id = await self._create_run(client, self._agent_id, full_prompt)
                except httpx.HTTPStatusError as exc:
                    if exc.response.status_code in {404, 410}:
                        self._agent_id = None
                        agent_id, run_id = await self._create_agent(client, full_prompt)
                        self._agent_id = agent_id
                    elif exc.response.status_code == 409:
                        await self._cancel_active_run(client, self._agent_id)
                        run_id = await self._create_run(client, self._agent_id, full_prompt)
                    else:
                        raise
            else:
                agent_id, run_id = await self._create_agent(client, full_prompt)
                self._agent_id = agent_id

            return await self._wait_for_result(client, self._agent_id, run_id)

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
        if response.status_code == 400:
            detail = self._error_detail(response)
            if "limit" in detail.lower() or "upgrade" in detail.lower():
                agent_id = await self._reuse_existing_agent(client)
                if agent_id:
                    self._agent_id = agent_id
                    run_id = await self._create_run(client, agent_id, prompt)
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
        self, client: httpx.AsyncClient, agent_id: str, prompt: str
    ) -> str:
        for attempt in range(3):
            response = await client.post(
                f"{CURSOR_BASE_URL}/v1/agents/{agent_id}/runs",
                headers=self._headers(),
                json={"prompt": {"text": prompt}},
            )
            if response.status_code == 409:
                await self._cancel_active_run(client, agent_id)
                await asyncio.sleep(POLL_INTERVAL_SEC * (attempt + 1))
                continue
            response.raise_for_status()
            return self._parse_run_id(response.json())
        raise RuntimeError("Cursor API: agent is busy (409), try again later")

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
