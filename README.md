# Cormak AI 3D Generator

Generate textured 3D models from text or an object photo, then download and import the GLB inside the Godot editor. The add-on is free and uses your existing Cormak account and AI credits for cloud generation.

## Installation

1. Use Godot 4.3 or newer.
2. Extract this repository or the release ZIP into your Godot project so that addons/cormak/plugin.cfg exists.
3. Open Project > Project Settings > Plugins and enable Cormak AI 3D Generator.
4. Open the Cormak dock, choose Login with Cormak, and complete sign-in in the browser on the same computer.

## Generate and import

Choose Text to 3D or Image to 3D, enter a description or select a PNG, JPEG, or WebP reference, and choose a quality preset. The dock shows the maximum credit cost before confirmation. If browser approval is required, approve the exact request in Cormak. When the build finishes, download the GLB, preview it, and add it to the active Node3D scene with Undo/Redo support.

Recent models shows the newest models in your Cormak library. If a connection is interrupted, resume the existing request before starting another one. Pause tracking and Stop tracking affect only local editor observation; an accepted cloud job can still finish and use credits.

## Network and privacy

This is an editor tool and does not add networking or authentication to your exported game. When used, the editor connects over HTTPS to mcp.cormak.app and Cormak storage. It sends only the text or photo submitted for generation; it does not send passwords, project contents, or unrelated files. Sign-in, spending approval, and purchases are handled in the browser.

Cormak connections: https://app.cormak.app/mcp
Privacy policy: https://cormak.app/privacy
3D Studio guide: https://cormak.app/blog/create-3d-model-with-ai

MIT license for the add-on source. Cormak service and generated outputs are governed by https://cormak.app/terms.
