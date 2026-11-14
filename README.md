# SHOUTcast Encoder (iPadOS)

Free/open-source SHOUTcast **v1** source client: microphone → LAME MP3 → DNAS.

- Swift / SwiftUI / AVAudioEngine / Network.framework
- MP3 encoding via [LAME](https://lame.sourceforge.io) (LGPL), built as a static lib
- Streams in the background (audio background mode), supports USB/Bluetooth mics
- Source password is not stored on disk

## Build (macOS + Xcode 15+)
    scripts/build_ipa.sh        # -> ShoutcastEncoder-unsigned.ipa

Or push to GitHub: the included Actions workflow builds the unsigned .ipa and
uploads it as an artifact.

Install the unsigned IPA with AltStore, Sideloadly, TrollStore, etc. (they sign it for you).

## Downloads
You can download this app without building on the [Releases](https://github.com/ArtTols/iShout/releases) page (stable-ish build) or in [Actions](https://github.com/ArtTols/iShout/actions) (bleeding edge build)

## Protocol notes
Connects to **listener port + 1**, sends `password\r\n`, waits for `OK2`, sends
`icy-*` headers, then streams MP3. Untick the port toggle if you want to enter the source port directly.

## License
GPL-3.0-or-later (see LICENSE).

## WARNING!
This app has been built with help of an AI assistant (Claude)
