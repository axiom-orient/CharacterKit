# Norwegian emotion assets

`ReactiveCharacterGIFView` uses twelve 288×288 GIFs and one shared neutral PNG.
Each GIF has twelve frames at 160 ms per frame and plays once. Every first and last
frame must decode to exactly the neutral PNG's RGBA pixels.

The source animations were generated in the user's ChatGPT conversation on
2026-11-13: [GIF request](https://chatgpt.com/c/6af6a4ee-1a5c-83e8-9c3c-b36fa7acc8f3).
Downloads are reviewed by expression before their filenames are mapped to the SDK's
emotion names. The first generated batch duplicated six positive emotions, so its
duplicates are excluded. Generated downloads and review contact sheets are not
runtime resources.

To reproduce the package files, put the reviewed originals in a separate directory,
named after all twelve `CharacterEmotion.rawValue` values with a `.gif` extension.
Install FFmpeg and [Gifsicle](https://www.lcdf.org/gifsicle/) through their official
distributions or a trusted package manager, then run:

```sh
swift Artwork/Norwegian/prepare_assets.swift /path/to/originals /tmp/norwegian-prepared
```

The tool preserves the authored middle frames, fits each canvas without stretching,
eases the boundary frames to one neutral image, and encodes all GIFs with a shared
128-color palette. Twelve frames are selected from each sixteen-frame original;
Gifsicle 1.98 then applies lossless frame-difference optimization. A lossy GIF pass was
excluded because it introduced visible speckle in the face. The tool writes the source
hashes alongside the results. Review the resulting
animations before copying the GIFs and neutral PNG into `Resources/Norwegian`.
Store the hash record here rather than in the runtime bundle.

`CharacterNorwegianGIFTests` checks all twelve resources, their dimensions, durations,
distinct middle frames, identical neutral boundaries, and one-shot completion.
Visual review is still required for the meaning and quality of each expression.
