# Diorama material atlas

Original AI-generated albedo atlas, created with the built-in image generation tool on 2026-10-14 for this project. No downloaded third-party artwork. Four equal quadrants: plaster, olive painted steel, asphalt, soil. Source retained as diorama-atlas.png.

Prompt: flat orthographic scanned albedo; four equal quadrants; neutral diffuse light; no objects, borders, text or baked directional lighting. Weathered warm gray plaster; faded olive paint with fine scratches; worn gray asphalt; muted brown soil/gravel. Restrained authentic military diorama palette.

Runtime uses mirrored interior quadrant coordinates, mipmaps and anisotropic filtering. This reduces obvious edge discontinuities and shimmer; it does not establish perfectly seamless measured PBR material maps. Roughness remains authored, not scanned. Canvas weave remains procedural. The atlas is shared by architecture, ground, road and equipment shaders. Equipment faction colors remain separate from wear.

Construction atlas: generated in the same session, four neutral albedo quadrants (terracotta tiles, galvanized corrugation, olive canvas, brick). Prompt requests orthographic 2×2-meter surfaces, diffuse light and no labels. Filtered in the same manner. Small baked shading remains in the generated samples; these are illustrative albedo assets, not calibrated scans.
