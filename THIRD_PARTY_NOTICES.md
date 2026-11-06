# Third-party notices

## WhisperKit 1.1.1

- Source: https://github.com/argmaxinc/WhisperKit
- Licence: MIT, Copyright (c) 2024 argmax, inc.
- Use: on-device speech-to-text (`Sources/WhisperEngine`).
- Model weights are downloaded at runtime from `argmaxinc/whisperkit-coreml` on Hugging Face (OpenAI Whisper weights, MIT) and are not redistributed in this repository.

## SpeakerKit models

- Source: https://huggingface.co/argmaxinc/speakerkit-coreml (Pyannote "community-1", converted to Core ML by Argmax)
- Licence: CC-BY-4.0.
- Use: telling meeting voices apart on device (`Sources/WhisperEngine/SpeakerSplitter.swift`).
- Downloaded at runtime into BugVoice's models folder; not redistributed in this repository.

## llama.cpp (tag b11829)

- Source: https://github.com/ggml-org/llama.cpp (release b11829, pinned by SHA-256 in `Scripts/llama-server.env`)
- Licence: MIT, Copyright (c) 2023-2026 The ggml authors. The release also bundles ggml (same project, same licence).
- Use: the `llama-server` helper and its dylibs in `BugVoice.app/Contents/Helpers/` run the built-in cleanup model on 127.0.0.1. Fetched and verified at build time by `Scripts/fetch-llama-server.sh`; the app never downloads an executable.

```
MIT License

Copyright (c) 2023-2026 The ggml authors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
