# X4LLM — AI Board Computer (Windows)

In-game LLM assistant for X4: Foundations. Adds an **AI** tab to the Information
sidebar so you can chat with an onboard "board computer" backed by a local
llama.cpp server.

## What's in this package
- `extensions/x4llm/`    — the AI board-computer extension (this package)
- `extensions/x4native/` — the X4Native native-bridge framework it depends on

Both are prebuilt for **Windows x86-64** (`.dll`). `x4llm.dll` is statically
linked and has no runtime dependencies beyond the Windows system libraries.

## Install
1. Copy **both** `x4llm` and `x4native` folders into your game's `extensions/`
   directory:
   ```
   <X4>\extensions\x4llm\
   <X4>\extensions\x4native\
   ```
2. In **Settings -> Extensions**, make sure **Protected UI Mode is disabled**.
3. Launch the game.
4. In the map, select a ship/station -> **Information** -> the **AI** tab
   (message-bubble icon). Type a question, press Enter.

> Running X4 under Steam Proton/Wine also works — the same `.dll` builds load
> through Proton.

## LLM server
The extension talks to a llama.cpp server over HTTP (OpenAI-compatible
`/v1/chat/completions`). Configure the endpoint and sampling in
`extensions\x4llm\x4llm_settings.txt` (edits apply live on the next query, no
restart needed):
```
llm_url=http://<host>:<port>/v1
model=<model>
temperature=0.7
max_tokens=1024
...
```
Set `llm_url` to the machine running llama.cpp as seen from the PC playing the
game (e.g. `http://127.0.0.1:5001/v1` if local, or the server's LAN IP).

## Requirements
- X4: Foundations Windows (x86-64)
- **Microsoft Visual C++ Redistributable** (for `x4native_core.dll`) — normally
  already installed alongside X4
- A running llama.cpp server (separate)

## Notes
- If the AI tab or LLM responses don't appear, check the extension logs under
  `<profile>\x4native\` in your X4 save folder.
