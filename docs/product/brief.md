# Terminal-owned tmux clipboard

## Approved outcome
Copy text from persistent tmux sessions and supported TUIs into the clipboard of the computer displaying WezTerm, both locally on Linux and over SSH from either Mac. Paste using WezTerm (Ctrl+Shift+V on Linux, Cmd+V on macOS). John approved this scope in the implementation conversation.

## Scope and risks
Use the existing OSC 52 path, replacing competing host-local tmux-yank behavior. Cover Helix, Lazygit, Yazi, Pi, Codex and Claude Code; document native-copy limitations and tmux-selection fallbacks. Preserve sessions during reload. No clipboard read bridge, SSH service, app patching or unrelated Yazi rule repair.

Value: resolves copying to the wrong computer. Usability: preserve vi copy mode and mouse selection. Feasibility: verify terminal bytes with isolated real tmux and TUI processes; real Linux/Mac clipboard delivery still needs manual checks. Viability: use existing pinned packages and built-in terminal behavior, not another service. This is durable configuration, not a disposable experiment.
