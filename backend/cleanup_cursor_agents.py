"""Delete all Cursor cloud agents to free plan slots."""
import os
import httpx
from dotenv import load_dotenv

load_dotenv()
key = os.getenv("CURSOR_API_KEY", "")
headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}

with httpx.Client(timeout=60.0) as client:
    r = client.get("https://api.cursor.com/v1/agents?limit=100", headers=headers)
    r.raise_for_status()
    items = r.json().get("items", [])
    print(f"Found {len(items)} agents")
    for item in items:
        agent_id = item["id"]
        try:
            dr = client.delete(
                f"https://api.cursor.com/v1/agents/{agent_id}",
                headers=headers,
                timeout=60.0,
            )
            print(f"DELETE {agent_id}: {dr.status_code}")
        except Exception as exc:
            print(f"DELETE {agent_id}: FAILED {exc}")
