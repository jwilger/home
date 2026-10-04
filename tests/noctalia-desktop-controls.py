"""Validate the real pinned plugin and both repository-owned Noctalia baselines."""
import pathlib
import sys
import tomllib

baseline, plugin = map(pathlib.Path, sys.argv[1:])
config = tomllib.loads((baseline / "config.toml").read_text())
state = tomllib.loads((baseline / "settings.toml").read_text())
manifest = tomllib.loads((plugin / "plugin.toml").read_text())
plugin_id = "maddingo/hypr-layout-switcher"
assert manifest["id"] == plugin_id
assert manifest["plugin_api"] == 3
assert manifest["version"] == "0.1.1"
assert manifest["widget"][0] == {"id": "toggle", "entry": "widget.luau"}
assert manifest["service"][0] == {"id": "poller", "entry": "service.luau"}
for entry in ("widget.luau", "service.luau"):
    assert (plugin / entry).is_file()
for document in (config, state):
    assert plugin_id in document["plugins"]["enabled"]
assert state["bar"]["main"]["center"] == [
    "spacer_8", "date", "clock", "spacer_2", "privacy", "spacer_3", "media", "spacer_7"
]
state_widgets = state["widget"]
assert state_widgets["active_window"] == {"capsule": True, "min_length": 50}
for spacer in ("spacer_7", "spacer_8"):
    assert state_widgets[spacer] == {"type": "spacer"}
assert config["bar"]["main"]["start"] == [
    "spacer", "workspaces", "spacer_5", "layout_switcher", "spacer_6", "active_window"
]
widgets = config["widget"]
assert widgets["layout_switcher"]["type"] == plugin_id + ":toggle"
assert widgets["workspaces"]["label_source"] == "name"
assert widgets["workspaces"]["max_label_chars"] == 1
assert widgets["workspaces"]["show_labels"] is True
assert widgets["workspaces"]["show_all_outputs"] is False
for spacer in ("spacer_5", "spacer_6"):
    assert widgets[spacer] == {"type": "spacer", "length": 20}
print("ok - pinned Noctalia plugin, enabled state, logical labels and bar order")
