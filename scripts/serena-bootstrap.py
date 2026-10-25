"""Start pinned Serena after resolving the MCP v1 SDK's forward reference."""
from mcp.server.fastmcp.server import Settings

# MCP v1 defines Settings before FastMCP; resolve the public model once both
# exist. Do not suppress warnings or change Serena's own settings configuration.
_ = Settings.model_rebuild()

from serena.cli import top_level

if __name__ == "__main__":
    top_level(prog_name="serena")
