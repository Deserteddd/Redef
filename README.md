# Project plan - Eelis Autio

An abstraction layer for window management and rendering on Windows. This project is split in two parts: The API and a demo.

## The API

The goal is to offer a simple API for:

- Creating and destroying a window
- Window controls
  - Resize                              [Done]
  - Fullscreen on/off                   []
  - Mouse mode (relative/absolute)      [Done]
- Querying the window                   [Done]
- Queyring IO-devices                   [Done]
- Event polling                         []
  - User events                         [Done]
  - OS events                           [Done]
- Creating and binding GPU resources:   [Done]
  - Shaders                             [Done]
  - Vertex buffers                      [Done]
  - Index buffers                       [Done]
  - Constant buffers                    [Done]
  - Textures                            [Done]
- Issuing draw calls (direct)           [Missing index controls]

## TODO

[]  Unify API by using vec2
[]  Unify enum casing

### Architecture

The top-level architecture can be seen by looking at the definition of **Global** (found in common.odin).

On initialization, the system creates a window with an associated graphics context and stores the pointers to these internally. Along with them, the system holds some other internal variables such as the keyboard state and event queue.

Since DirectX 11 itself operates as a state machine, and the management of GPU resources will be a user-level feature, the system itself doesn't generally need to keep track of GPU-related state. All GPU-related state will be stored in the **Graphics** struct (eg. pointers to things like the swapchain and device context).

## The Demo

a game-like program that fully leverages the features provided by the API.

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

- Odin standard library
- Win32
- DirectX 11
- stb_image
- cgltf (If I decide to go the glTF route)

### Tools

- Git
- Rad debugger
- VSCode (+ LSP)

## Contribution

This is a solo project. Judging by the git history, I must have already spent at least 50 hours on this and it's not even half done.
