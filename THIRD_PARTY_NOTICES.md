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
