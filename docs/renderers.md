# Choosing a renderer

The renderer is the part that will cost you the most time, so this is written
as a decision procedure rather than a list of options.

## Start here

Set `RENDERER="native"` and run the game. Wine's own OpenGL sometimes works,
and when it does you get the best performance available with no extra parts.

If it dies with a page fault at address `0`, or a `Could not create gl context`
dialog, move on.

## Then try Mesa

Set `RENDERER="mesa-llvmpipe"`. This installs Mesa's `opengl32.dll` and
`libgallium_wgl.dll` next to the game and overrides `opengl32` to native for
that executable only.

It renders on the CPU. It is reliable precisely because it does not depend on
anything about your GPU, your driver, or Wine's windowing code.

**If it works, lower the in-game render scale before doing anything else.**
llvmpipe cost scales with pixel count, so 70% render scale is close to half the
work of 100%. No environment variable comes close to that effect.

## GPU paths, and why they often fail

`mesa-zink` runs OpenGL on top of Vulkan, which MoltenVK maps to Metal. When it
works you get real GPU acceleration. It frequently does not work, failing with:

```
Could not create window: No matching GL pixel format available
```

Mesa's WGL layer, running on Wine's Vulkan implementation, cannot always offer
a pixel format the game will accept. It is worth one attempt because the payoff
is large, and it costs a single launch to find out.

`dxmt` translates Direct3D 11 to Metal. It only helps games whose engine
actually calls D3D11.

## The trap: D3D11 symbols mean nothing

A binary containing `D3D11CreateDevice`, `IDXGISwapChain`, and friends is
**not** evidence that the game uses Direct3D 11. Any game built on SDL ships
every backend SDL was compiled with, used or not.

Mewgenics contains a complete SDL3 D3D11 renderer, plus strings for `vulkan`,
`metal`, `opengles2` and `software`. It uses none of them. Its engine draws in
OpenGL directly, so `SDL_RENDER_DRIVER` is ignored entirely.

We spent an hour compiling LLVM 15 to enable a code path the game never calls.

## Verify, do not assume

```bash
./winmac status <game>
```

with the game running. It prints CPU percentage, GPU utilization, and the
graphics libraries the process has actually loaded.

```
CPU 871%   RAM 2990 MB
Loaded: dxgi.dll libgallium_wgl opengl32.dll winemetal
GPU utilization: 0%
```

Read that carefully: `dxgi.dll` and `winemetal` are loaded, which looks like
DXMT is working. It is not. The CPU is at nearly nine cores and the GPU is
idle, and `libgallium_wgl` is present. Those libraries were probed and
discarded. The drawing is happening on the CPU.

Loaded libraries alone will mislead you. The CPU and GPU numbers are what
settle it.
