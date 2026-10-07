"""Verify a local stdio MCP server initializes and advertises tools; no game import."""
import argparse
import asyncio
import json
from datetime import timedelta
from pathlib import Path
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


async def verify(command, arguments):
    params = StdioServerParameters(command=command, args=arguments)
    async with stdio_client(params) as (reader, writer):
        async with ClientSession(reader, writer, read_timeout_seconds=timedelta(seconds=45)) as session:
            init = await session.initialize()
            tools = await session.list_tools()
            result = {"server":init.serverInfo.model_dump(), "advertised_tools":len(tools.tools),
                      "tool_names":[t.name for t in tools.tools]}
            if "list_instances" in result["tool_names"]:
                reply = await session.call_tool("list_instances", {})
                result["list_instances"] = reply.model_dump(mode="json")
            return result


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("command")
    p.add_argument("arguments", nargs=argparse.REMAINDER)
    a = p.parse_args()
    result = asyncio.run(verify(a.command, a.arguments))
    a.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps({"server":result["server"],"advertised_tools":result["advertised_tools"]},indent=2))
