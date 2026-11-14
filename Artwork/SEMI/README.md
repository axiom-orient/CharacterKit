# SEMI authoring inputs

The authoring tool retains three inputs from the supplied `CharacterKit-SEMI-commercial-final-20261006-v17` artwork:

| Input | Role |
|---|---|
| [semi-document-cat-preview.png](semi-document-cat-preview.png) | Registered 512×512 RGBA preview used for head, paws and tail |
| [registered-ear-left.png](registered-ear-left.png), [registered-ear-right.png](registered-ear-right.png) | Authoritative 512×512 RGBA ear layers; original mask/color recipe is unavailable |

The ear inputs and bundled runtime ears are intentionally separate authoring and runtime boundaries. The generator validates and copies those bytes. The preview supplies the remaining four layers.

Six registered layers in [Resources/SEMI](../../Sources/ReactiveCharacterKit/Resources/SEMI) feed the shared pose/scene pipeline. Eyes, nose, mouth, document and articulation are live vectors. Preserve the 512px registration when editing inputs.

```sh
python3 -m venv /tmp/characterkit-artwork
/tmp/characterkit-artwork/bin/python -m pip install -r Artwork/SEMI/requirements.txt
/tmp/characterkit-artwork/bin/python Artwork/SEMI/prepare_assets.py --output /tmp/characterkit-semi-review
```

[prepare_assets.py](prepare_assets.py) accepts explicit preview, ear and output paths. It writes six named files and leaves unrelated output files intact; the default output is the package resource directory. [Pinned dependencies](requirements.txt) are the recorded authoring environment. A prior check matched decoded RGBA for all six layers; ears also matched encoded bytes, while encoding of the other layers may vary. Review generated assets before replacing bundled resources.
