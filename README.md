# Husky

Dictation and meeting transcripts for the Mac, local and free. Hold a key, talk, let go: the text lands wherever your cursor is. A listening orb in your menu bar shows when it hears you.

Husky is a personal fork of [Andrew Dictate](https://github.com/jassuwu/andrew-dictate) by [jass](https://jass.gg), by way of [Suriya's fork](https://github.com/suriyavasan/andrew-dictate). Thank you both.

## What's different from Andrew Dictate

- **A listening orb** instead of the gold line: pick one of nine orbs from [ThinkingOrbsKit](https://github.com/Jakubantalik/Libraries.dev). It grows and shrinks with your voice, and lives in the menu bar too.
- **A redesigned app** in the Mac's own style: Light or Dark, your Mac's accent colour, Liquid Glass. That covers Settings (now with a Home dashboard), the menu bar panel, Meetings, Setup and About.
- **Fix a Word from anywhere** with a global shortcut, ⌃⌥F by default.

## Dictate

Hold `fn`, talk, let go. Double-tap `fn` to talk hands-free; `esc` throws it away. A dictionary fixes words it keeps mishearing. English, or 25 languages.

## Meetings

Press record in the menu bar, or say yes when it asks at the start of a call. It never starts by itself. Your mic is you, and whatever the Mac plays is them. Stop, and you get one Markdown file with the speakers split out.

## Install

Apple silicon, macOS 26. Build it yourself:

```sh
cd apps/mac
xcodegen generate
xcodebuild -project AndrewDictate.xcodeproj -scheme AndrewDictate -configuration Release \
  -derivedDataPath .build-release build
cp -R ".build-release/Build/Products/Release/Husky.app" /Applications/
```

For development, `apps/mac/dev.sh` builds and runs **Husky Dev**, which has its own permissions and data.

## Credits

Original app: [Andrew Dictate](https://github.com/jassuwu/andrew-dictate) by [jass](https://jass.gg), MIT. Fork: [Suriya](https://github.com/suriyavasan/andrew-dictate).

[FluidAudio](https://github.com/FluidInference/FluidAudio) apache-2.0 · [parakeet](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) cc-by-4.0 · [WhisperKit](https://github.com/argmaxinc/WhisperKit) mit · [whisper](https://github.com/openai/whisper) mit · [whistle](https://huggingface.co/Cactus-Compute/whistle) apache-2.0 · [silero vad](https://github.com/snakers4/silero-vad) mit · [ThinkingOrbsKit](https://github.com/Jakubantalik/Libraries.dev) mit

[MIT](LICENSE).
