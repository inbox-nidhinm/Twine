# Connecting AI apps to Twine

Twine speaks MCP (the Model Context Protocol), so Claude, Cursor and other AI apps can work in the open project: read it, add and change layers, actions, presets and templates, draw frames to check their work, bring files in and export. Every change shows in Twine at once and undoes with ⌘Z like your own.

Twine must be allowed: Settings > AI apps > Let AI apps use Twine (on unless you turned it off). Twine needs to have been opened once since this was built; after that, an AI app opens it in the background when it needs it.

Each AI app is pointed at Twine's own program with `--mcp`. With Twine in `build/`, that is:

```
/Users/nidhinmohammad/Documents/Claude Code/Twine/build/Twine.app/Contents/MacOS/Twine --mcp
```

If you move Twine (to Applications, say), connect the AI apps again with the new path. Settings > AI apps > Copy Command always gives the current one for Claude Code.

## Claude Code

Paste the command from Settings > AI apps > Copy Command into a terminal, or run:

```bash
claude mcp add --scope user twine -- "/Users/nidhinmohammad/Documents/Claude Code/Twine/build/Twine.app/Contents/MacOS/Twine" --mcp
```

## Claude for Mac

Settings > Developer > Edit Config opens `claude_desktop_config.json`. Add Twine to its `mcpServers` and restart Claude:

```json
{
  "mcpServers": {
    "twine": {
      "command": "/Users/nidhinmohammad/Documents/Claude Code/Twine/build/Twine.app/Contents/MacOS/Twine",
      "args": ["--mcp"]
    }
  }
}
```

## Cursor and others

Most apps take the same `command` and `args` (Cursor in `~/.cursor/mcp.json`, under `mcpServers`).

## What the AI can do

| Tool | What it does |
|---|---|
| `get_status`, `get_project`, `describe` | Read what is open, the project's layers and actions, and Twine's lists of actions, presets, templates and easings |
| `list_projects`, `open_project`, `new_project` | Find, open and make projects (from a template too) |
| `add_layer`, `update_layers`, `delete`, `arrange_layers` | Shapes, text and frames; their look and place; grouping, framing, masking and stacking |
| `add_action`, `add_preset`, `update_actions` | Animate: any action, any preset, with timing and easing |
| `add_template` | A template, filled with your pictures |
| `set_composition`, `set_view`, `undo` | Size, length and background; Design or Animate, the playhead and the selection; undo and redo |
| `render_frame`, `import_media`, `export` | Draw a frame as a picture, bring files in, export a movie, GIF or still |
