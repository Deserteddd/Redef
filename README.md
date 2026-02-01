# Project plan

An abstraction layer for window management and rendering on Windows. This project is split in two parts: The API and a demo.

## The API

The goal is to offer a simple API for:

- Creating and destroying a window
- Window controls
  - Resize
  - Fullscreen on/off
  - Mouse mode (relative/absolute)
- Event polling
  - User events
  - OS events
- Creating and binding GPU resources:
  - Shaders
  - Vertex buffers
  - Index buffers
  - Constant buffers
  - Textures
- Issuing draw calls (direct)

### Architecture

The top-level architecture can be seen by looking at the definition of **Global** (found in common.odin).

On initialization, the system creates a window with an associated graphics context and stores the pointers to these internally. Along with them, the system holds some other internal variables such as the keyboard state and event queue. The initialization can be 

Since DirectX 11 itself operates as a state machine, and the management of GPU resources will be a user-level feature, the system itself doesn't generally need to keep track of GPU-related state. The **Graphics** struct will hold pointers to things like the swapchain and device context, but these resources are internally managed by DX11.

## The Demo

Game-like program that fully leverages the features provided by the API.

### Includes

- Movable camera
- Asset importing (either OBJ-format without external libraries or glTF with an external importer)
- Vertex shader
- Multiple pixel shaders

### (Lack of) Architecture

This demo is not meant to be a large project like a game engine. For this reason, there is not much to talk about here. The program only has two parts: setup and run.

## Tech stack

### Languages

- Odin (a great language btw)
- HLSL (for writing shaders)

### Libraries

- Win32
- DirectX 11
- cgltf (If i decide to go the glTF route)

### Tools

- Git
- Rad debugger
- VSCode (+ LSP)

## Contribution

This is a solo project. Judging by the git history, I must have already spent at least 50 hours on this and it's not even half done.
