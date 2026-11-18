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

Apple silicon, macOS 26.

```sh
brew install --cask rishikhesh/tap/husky
```

It lives in the menu bar as an orb; there's no Dock icon. Setup asks for the microphone and Accessibility, and which jobs you want: dictation (~460 MB) and, if you tick it, meetings (~2.9 GB).

Husky is signed with a developer certificate but not notarized, so the cask clears the download quarantine for you. Prefer a file? Get the DMG from [Releases](https://github.com/Rishikhesh/husky/releases).

## Update

Husky checks once a day and the menu says when a new version is out; one click updates it through Homebrew. Or:

```sh
brew upgrade --cask rishikhesh/tap/husky
```

Your permissions carry over, because every release is signed the same way.

## Build it yourself

```sh
cd apps/mac
./dev.sh          # builds and runs Husky Dev, with its own permissions and data
./release.sh 0.14.1   # maintainers: tests, signs, publishes the release and the cask
```

## Credits

Original app: [Andrew Dictate](https://github.com/jassuwu/andrew-dictate) by [jass](https://jass.gg), MIT. Fork: [Suriya](https://github.com/suriyavasan/andrew-dictate).

[FluidAudio](https://github.com/FluidInference/FluidAudio) apache-2.0 · [parakeet](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) cc-by-4.0 · [WhisperKit](https://github.com/argmaxinc/WhisperKit) mit · [whisper](https://github.com/openai/whisper) mit · [whistle](https://huggingface.co/Cactus-Compute/whistle) apache-2.0 · [silero vad](https://github.com/snakers4/silero-vad) mit · [ThinkingOrbsKit](https://github.com/Jakubantalik/Libraries.dev) mit

[MIT](LICENSE).
