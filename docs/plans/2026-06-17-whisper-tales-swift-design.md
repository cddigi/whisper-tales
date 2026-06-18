# WhisperTales — Design (Swift / Apple-native, on-device)

> A from-scratch, privacy-first native Apple app. A parent records their voice; the app
> clones it **on-device** and narrates personalized bedtime stories in the parent's own
> voice for their child. It also folds in conversational voice-interaction and dictation.
> 100% local / offline.
>
> **Status:** Design — pre–Stage 0. Several load-bearing technical facts (the
> `mlx-audio-swift` reference-audio cloning API, model sizes, and repack licenses) are
> **unverified** and are the explicit subject of Stage 0. Where this doc states an API
> name or number that Stage 0 has not yet confirmed, it is marked **(verify)**.

---

## 1. Overview & Goals

### What WhisperTales is
A native Apple (iOS / iPadOS / macOS) app that lets a parent:
1. **Record and clone their voice on-device** from a short reference sample.
2. **Generate personalized bedtime stories** (text) on-device, tailored to their child.
3. **Narrate those stories in the parent's own cloned voice**, so a child can hear a new
   bedtime story from a parent who can't physically be there.
4. **Interact by voice** — short spoken requests from a child ("tell me a story about a
   brave little fox") and free-form **dictation** from a parent — via Apple's first-party
   on-device speech-to-text.

### Primary user value
For working, travelling, military, and separated/divorced parents (children ~3–12) who
can't always be at bedtime: a child still hears a *new* story *in their parent's voice*,
with no usable voice or personal data leaving the device.

### Core principles
- **Local / offline for all user content and inference.** No analytics, no accounts, no
  server, no cloud model calls. The only network events are OS-level, content-free asset
  fetches, and they are disclosed (§8, §10, §15).
- **Honest claims.** We say **cryptographic erasure**, not "DoD wipe"; we scope the
  offline and at-rest guarantees to what the platform actually delivers (§8).
- **Boring, idiomatic SwiftUI + SwiftData.** Protocol seams only where we genuinely swap
  implementations (the ML services and the key store) — not a parallel architecture on top
  of the framework. Heavy work runs in actors off the main thread.

### Non-Goals / YAGNI for v1
**External scope:**
- No cloud / Private Cloud Compute generation — on-device `SystemLanguageModel` only.
- No iCloud sync / family sharing / accounts / telemetry.
- No voice export or sharing of cloned-voice audio out of the app.
- No multi-language narration at launch (English first).
- No Intel Mac, watchOS, tvOS, or visionOS targets.
- No always-listening background assistant — voice requests are explicit and foreground.

**Internal scope (deliberately deferred to keep v1 small — see §15):**
- **One** TTS model behind one protocol — no swappable model registry.
- **In-memory** serial synthesis queue — no persisted/durable job system.
- **Human parental approval** as the safety gate — no automated second-pass content rater.
- AES-256 data key in the Keychain — no Secure Enclave key-wrapping in v1.

---

## 2. Target Platforms & Hardware Requirements

The device floor is the **intersection** of three on-device ML stacks: **MLX/Metal** (TTS
cloning), **Foundation Models** (Apple-Intelligence class), and **SpeechAnalyzer/
SpeechTranscriber**. The **binding constraint is Foundation Models** (Apple-Intelligence
capable), which is stricter than `mlx-swift`'s own software minimums.

> **This is a product / go-to-market decision, not a footnote.** Apple-Intelligence-capable
> iPhones are a *minority* of the active installed base in 2026 (A17 Pro / iPhone 15 Pro and
> newer). Restricting the paid app to those devices is a large addressable-market cut and
> must be accepted deliberately. The mitigation is a **degraded tier** (see below), offered
> as an intentional lower-tier product — not merely an error path.

### Software floor
- **OS:** iOS 26 / iPadOS 26 / macOS 26 (required for the `Speech` `SpeechAnalyzer` stack
  and `FoundationModels`).
- **Build:** Xcode 27 + Swift 6.2 toolchain. Package minimums for `mlx-swift` /
  `mlx-audio-swift` are lower (≈ macOS 14 / iOS 17, Swift 5.9+ **(verify against the pinned
  commit's `Package.swift`)**), but our OS floor is higher because of the Apple-Intelligence
  APIs.
- **Beta-tooling constraint (hard):** **No commercial App Store submission until Xcode 27
  and iOS/macOS 26 reach GM.** App Store Connect does not accept production builds from a
  beta SDK. "GM toolchain available" is an explicit external milestone gating Stage 6 (§14).

### Hardware floor (the real constraint)
| Platform | Minimum | Why |
|---|---|---|
| iPhone | iPhone 15 Pro / Pro Max or iPhone 16+ (A17 Pro+, **8 GB+** unified memory) | Foundation Models needs Apple-Intelligence-class silicon; MLX needs Metal + RAM headroom for a multi-hundred-MB quantized model |
| iPad | A17 Pro or M-series (**8 GB+**) | Same |
| Mac | Any Apple Silicon Mac (M1+). **Intel categorically excluded.** | MLX requires Apple Silicon + Metal |

### Degraded tier (deliberate, for capable-OS-but-not-Apple-Intelligence devices, or users who disabled Apple Intelligence)
Story **generation** requires Foundation Models. Where it is unavailable —
`SystemLanguageModel.default.availability != .available`, including the user toggling Apple
Intelligence **off** or region/language gating — the app still delivers its core value via
**parent-written / parent-recorded stories narrated in the cloned voice**, with no on-device
generation. This is a stated, supported, lower-tier mode, surfaced as such in onboarding.

### Testing & memory cautions
- **MLX does not run in the iOS Simulator.** All inference-path QA (cloning, narration) runs
  on **physical Apple Silicon devices**. CI cannot validate the ML path without a
  hardware runner (self-hosted Mac runner, or a documented manual-on-device gate) — see §12.
- **Two distinct budgets, not one:**
  - **On-disk bundle size** vs the iOS app-size ceiling (§10).
  - **Peak resident memory during synthesis** (weights + activations + audio buffers) vs the
    ~8 GB-device jetsam ceiling. This is the real cliff. Stage 0 sets a **hard numeric
    go/no-go** (e.g. *peak RSS < ~3 GB on an 8 GB device, or drop to a smaller model*).
- The exact `SpeechTranscriber` device-support set and per-locale model sizes are not
  published by Apple — **medium confidence** (§15). Always gate at runtime (next section).

---

## 3. High-Level Architecture

Three layers. SwiftData `@Model` types **are** the domain entities (no parallel value-type
model). Protocol seams exist **only** on the ML services and the key store — the places we
actually substitute fakes in tests. Heavy inference runs in actors. Large binaries live as
encrypted files outside the database.

```
┌──────────────────────────────────────────────────────────────────────┐
│  PRESENTATION  (SwiftUI Views + @Observable, @MainActor ViewModels)    │
│                                                                        │
│   Child Mode (default, un-gated)     Parent/Admin Mode (gated)         │
│   • Active-child avatar picker       • Voice Onboarding / Training     │
│   • Library (per-child, @Query)      • Story Authoring (gen/dictate)   │
│   • Bedtime Player + sleep timer     • Review & Approve gate           │
│   • Voice Request (+ picture grid)   • Child & Voice profiles, Data    │
└───────────────┬────────────────────────────────────────┬─────────────┘
                │ ViewModels call services / use cases     │ @Query reads (library)
┌───────────────▼────────────────────────────────────────▼─────────────┐
│  WORKFLOWS  (use cases ONLY where they coordinate ≥2 services)         │
│   • TrainVoiceUseCase    (quality-gate → clone → encrypt → persist)    │
│   • GenerateStoryUseCase (generate page-by-page → persist as draft)    │
│   • NarrateStoryUseCase  (synthesize → encrypt-store → index segments) │
│   (Play / VoiceRequest / data-management are methods on a service/VM)  │
└───────────────┬────────────────────────────────────────┬─────────────┘
                │ protocol seams (ML + keys)               │ repository (SwiftData)
┌───────────────▼───────────────┐   ┌─────────────────────▼─────────────┐
│  ML SERVICES (actors)         │   │  PLATFORM / STORAGE SERVICES       │
│  • SpeechService              │   │  • StoryStore (SwiftData repo)     │
│    (Apple Speech: STT)        │   │  • AudioFileStore (files+CryptoKit)│
│  • VoiceSynthesisService      │   │  • ModelAssetStore (LOCAL loader)  │
│    (mlx-audio-swift)          │   │  • KeyStore (Keychain SymmetricKey)│
│  • StoryTextService           │   │  • ParentalGate (LocalAuth + PIN)  │
│    (FoundationModels)         │   │  • AudioCapture / Playback (AVF)   │
└───────────────────────────────┘   │  • NetworkSentinel (egress guard)  │
                │                    └────────────────────────────────────┘
        Metal GPU / Neural Engine            Local filesystem (encrypted),
        (MLX, Apple Intelligence)            Keychain, optional Secure Enclave
```

### Narrative
- **Presentation** is plain SwiftUI. View models are `@Observable` and `@MainActor`; the
  **library list reads SwiftData directly with `@Query`** (so the UI auto-updates), while
  **writes and multi-service workflows go through a service / use case**. We do *not* route
  every read through a repository protocol — doing so would forfeit `@Query`'s automatic
  observation. The repository protocol exists to make writes and tests explicit, not to hide
  reads the view should observe.
- **Workflows** are use cases that exist **only** where they coordinate more than one
  service. Single-service actions (play, delete, voice-request matching) are methods on the
  relevant service or view model — no pass-through ceremony.
- **ML Services** are Swift **actors** so MLX synthesis, Foundation Models generation, and
  streaming STT never block `@MainActor`. A **single in-memory serial actor** sequences
  synthesis jobs (one story at a time) so we never thrash GPU/RAM.
- **Dependency injection is plain initializer injection.** `AppDependencies` is a struct
  built once at `@main` that constructs the object graph; view models receive their
  collaborators via `init` and are placed in the SwiftUI environment by `RootView`. No
  service locator, no global container.
- **One platform seam, made explicit:** `ModelAssetStore` and `AudioSessionController` are
  protocols with an iOS and a macOS implementation selected at the composition root — not
  `#if os(...)` scattered through service bodies.

---

## 4. Core Components & Modules

Each lists its single responsibility and key Swift types. *(proposed)* = our types;
unmarked are Apple/package types. **(verify)** flags a name Stage 0 must confirm.

### 4.1 Speech-to-Text — `SpeechService` *(proposed protocol)*
**Responsibility:** the *input/utility* path only — **never narration**. Three uses, and
they map to **two different Apple modules**:
- **Parent dictation of a custom story (free-form, punctuation-sensitive):** use
  **`DictationTranscriber`** — Apple's punctuation/sentence-aware module built for exactly
  this. (Not a "fallback"; it is the right tool here.)
- **Short child voice requests / commands ("tell me the fox story"):** use
  **`SpeechTranscriber`** with a live preset.
- **Transcribing a recorded segment into editable text:** file path via the offline preset.

Backing: `import Speech` → `SpeechAnalyzer` (final actor session manager), `SpeechTranscriber`,
`DictationTranscriber`, `SpeechDetector` (VAD gating for hands-free child prompts),
`AnalyzerInput` (wraps `AVAudioPCMBuffer`), `AssetInventory` (locale model provisioning).

**Device & asset gating (corrected):**
- **Hardware support:** `SpeechTranscriber.supportsDevice()` — this is the device-class
  check that decides whether the high-quality module is usable at all.
- **Asset readiness:** `SpeechTranscriber.isAvailable` / `installedLocales` — whether the
  locale model is downloaded and ready (a *separate* concern from hardware).
- Implementation `AppleSpeechService` *(proposed, actor)* selects module by **use case**
  first, then degrades on `supportsDevice() == false`.

### 4.2 Voice Cloning + Narration — `VoiceSynthesisService` *(proposed protocol)*
**Responsibility:** the *output/narration* path — approved story text + a parent voice
profile → narrated audio in the parent's voice. **This is the product's highest-risk
component and the subject of Stage 0 (§14).**

- Protocol: `VoiceSynthesizing` *(proposed)*: `makeProfile(from:) async throws ->
  VoiceProfileArtifact` and `synthesize(text:using:) -> AsyncThrowingStream<SynthesizedChunk, Error>`.
- Backing package: `mlx-audio-swift` (SwiftPM, MIT), with **`MLXAudioTTS` + `MLXAudioCore`
  + `MLXAudioCodecs`** — the codecs module is needed because the reference-audio path takes
  raw samples (`MLXArray`), so a recorded WAV must be **decoded to an `MLXArray` first**.
- **Unverified API surface (Stage 0 must confirm before any app code):**
  - The package's documented TTS models are **Qwen3-TTS, Fish Audio S2 Pro, Soprano,
    VyvoTTS, Orpheus, MOSS-TTS, Marvis, Pocket TTS, Irodori TTS** — the README does **not**
    list Chatterbox, and it documents *preset speaker voices*, not a reference-audio cloning
    entry point.
  - The generate call uses a trailing `parameters:` label with a `GenerateParameters` struct
    **(verify)**; `refAudio` is `MLXArray?` **(verify)**. The exact reference-audio cloning
    symbol is **TBD** — Stage 0's first gate is a literal API-existence check (§14).
  - **Model loading must be local-only.** Do **not** call `fromPretrained(repoID)` anywhere
    in shippable code — that is the Hugging Face Hub **download** path and a network call.
    Implement an explicit bundled-file-URL loader (`loadModel(fromBundledURL:)` *(proposed)*)
    and verify no Hub identifier string is reachable (§8 egress guard).
- Implementation `MLXVoiceSynthesisService` *(proposed, actor)*. Loads bundled quantized
  weights from `ModelAssetStore`. v1 ships **one** model (no registry); see §10 for the
  candidate-selection decision and licensing gate.

### 4.3 Story Text Generation — `StoryTextService` *(proposed protocol)*
**Responsibility:** generate bedtime-story *text* on-device; never narration.
- Backing: `import FoundationModels` → `SystemLanguageModel.default`, `LanguageModelSession`,
  `@Generable` / `@Guide`, `GenerationOptions`, `LanguageModelSession.GenerationError`.
- Implementation `FoundationModelStoryService` *(proposed, actor)*. On-device only (never
  PCC). Generates **page-by-page** (§6). Gates on `SystemLanguageModel.default.availability`.

### 4.4 Audio Capture / Playback — `AudioCapture` / `AudioPlaybackEngine` *(proposed)*
- Capture: `AVAudioEngine` + `installTap(onBus:bufferSize:format:)`, `AVAudioConverter`
  (mic → analyzer format), `AVAudioPCMBuffer`; `AVAudioSession` on iOS.
- Playback: `AVAudioPlayer`/`AVAudioEngine`, `.playback` session for background/lights-out,
  **`MPNowPlayingInfoCenter` / `MPRemoteCommandCenter` with a locked-down command policy**
  (§9), interruption handling for calls/alarms, sleep-timer via `Task`.

### 4.5 Persistence — `StoryStore` *(proposed repository protocol over SwiftData)*
- Backing: **SwiftData** — `@Model`, `@Relationship`, `ModelContainer`, `ModelContext`,
  `ModelConfiguration(url:, cloudKitDatabase: .none)`. `@Model` types are the domain
  entities. The library view uses `@Query` directly; writes go through `StoryStore`.

### 4.6 Encrypted file storage — `AudioFileStore` / `ModelAssetStore` *(proposed)*
- `FileManager` under `Application Support`, `FileProtectionType.complete` /
  `.completeUnlessOpen`, `CryptoKit` `AES.GCM` envelope encryption, `SymmetricKey`.
- `ModelAssetStore` exposes only a **local bundled-URL** load path (no network).

### 4.7 Keys & parental gate — `KeyStore` / `ParentalGate` *(proposed)*
- `KeyStore`: per-asset `SymmetricKey` in the Keychain
  (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`). **No Secure Enclave wrapping in v1**
  (deferred, §15). **Never** protect the *data key* with `.biometryCurrentSet` — re-enrolling
  Face ID would destroy irreplaceable voice data.
- `ParentalGate`: `LocalAuthentication` `LAContext` **plus a separate app-level parent PIN**
  for destructive/sensitive actions, because `.deviceOwnerAuthentication` falls back to the
  device passcode the child also knows on a shared device (§8).

### 4.8 Network sentinel — `NetworkSentinel` *(proposed)*
**Responsibility:** prove the offline guarantee at runtime. A `URLProtocol` interceptor /
`NWPathMonitor`-backed guard that, in debug/CI, **fails** if any outbound socket opens
during an inference path, except the explicitly allow-listed, user-initiated `AssetInventory`
locale install (§8, §12).

### 4.9 Orchestration use cases *(proposed — only the multi-service ones)*
`TrainVoiceUseCase`, `GenerateStoryUseCase`, `NarrateStoryUseCase`. Each is a small struct
with init-injected protocol dependencies, holding workflow logic and error mapping.

---

## 5. Voice Processing Pipeline

Not a uniform "chain of stages" — the stages have different shapes (capture is a *stream*,
storage is *one-shot*, playback is *stateful*). It is: a **recording** stage, an **STT
utility**, and a **narration workflow**. Protocol seams live on the two ML services and the
key store; everything else is called directly.

```
 RECORD ──► STT (utility only) ──► VOICE PROFILE ──► NARRATION ──► STORE ──► PLAYBACK
 mic capture  requests/dictation/   decode ref→clone   synthesize     encrypt   bedtime
 (AVAudio     transcribe (Apple     artifact (mlx-     approved text   + index   player
  Engine)     Speech, by use case)  audio-swift)       in parent voice (files+DB)(AVF + MPNowPlaying)
```

### Key types *(proposed)*
```swift
// STT — INPUT/UTILITY ONLY. Never produces narration.
protocol SpeechService {
    // Free-form parent dictation (DictationTranscriber under the hood).
    func dictate(locale: Locale) -> AsyncThrowingStream<TranscriptionUpdate, Error>
    // Short child command (SpeechTranscriber under the hood).
    func recognizeCommand(locale: Locale) -> AsyncThrowingStream<TranscriptionUpdate, Error>
    // File → editable text.
    func transcribe(file: AVAudioFile, locale: Locale) async throws -> TranscriptionResult
    static func supportsHighQualityOnThisDevice() -> Bool   // SpeechTranscriber.supportsDevice()
}

// Cloning + narration — the ONLY producer of narrated audio.
protocol VoiceSynthesizing {
    func makeProfile(from reference: AudioReference) async throws -> VoiceProfileArtifact
    func synthesize(text: String, using artifact: VoiceProfileArtifact)
        -> AsyncThrowingStream<SynthesizedChunk, Error>
}
```
`SynthesizedChunk` is a thin wrapper we map from `mlx-audio-swift`'s actual stream event type
**(verify exact event cases in Stage 0)** — do not assume `.token/.audio/.info` without
confirming against the pinned commit.

### Stage detail
1. **Record.** `AudioCapture` installs an `AVAudioEngine` tap. For STT, each buffer is
   converted via `AVAudioConverter` to `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)`
   — **mandatory**; skipping it yields garbage transcription. For voice training, raw
   high-quality buffers are written **directly to a `.complete`-protected file and encrypted
   immediately**; no lingering plaintext intermediate (§8).
2. **STT (scoped).** Apple `Speech` is the sole STT path, never narration. Module chosen by
   use case (§4.1). Live presets: **`.progressiveLiveTranscription`**; file:
   **`.offlineTranscription`** *(verify alternative/time-indexed preset names at GM)*.
   **Gotcha:** finishing the input `AsyncStream` continuation does **not** end the session —
   call `finalizeAndFinishThroughEndOfInput()` (do it in a `defer`).
3. **Voice profile / clone.** A quality gate g&#40;length/SNR/clipping&#41; runs on the ~5–10 s
   reference; optional denoise. The recorded WAV is **decoded to an `MLXArray`** (codecs)
   then passed to the package's reference-audio cloning call **(API verified in Stage 0)**.
   The artifact + reference are encrypted at rest (§8). Keep the inaudible **PerTh
   watermark** the model embeds (license requires it; provenance only — §8).
4. **Narration.** `synthesize` streams chunks for **approved** text only (§6 gate), in an
   actor on the in-memory serial queue, honoring `Task.isCancelled`. **Rendered at approval/
   authoring time, ahead of bedtime** — never lazily at play time (§9).
5. **Store.** Chunks → encrypted file in `Application Support/audio/`; an `AudioAsset` row
   (relative path, sha256, key tag, sample rate) links to the `StorySegment`.
6. **Playback.** Decrypt **in memory** (no decrypt-to-temp) and play via AVFoundation under
   `.playback`, honoring the sleep timer and the locked-down remote-command policy (§9).

---

## 6. Story Generation

### Engine
On-device **`FoundationModels`** only — `SystemLanguageModel.default` via
`LanguageModelSession`. **Never Private Cloud Compute.** Gate the whole feature on
`availability == .available`; otherwise fall to the degraded tier (§2, §11). Note that a
parent can **disable Apple Intelligence** or be region/language-gated even on capable
hardware — handle that as the same degraded path, not a crash.

### The 4,096-token on-device context window is a first-class design driver
Prompt + instructions + transcript + response share one ~4,096-token budget; exceeding it
throws `GenerationError.exceededContextWindowSize`. So we **generate page-by-page**, never
one long free-form call:

```swift
@Generable
struct StoryPage {
    @Guide(description: "One short paragraph; gentle, simple vocabulary, calm bedtime tone")
    var text: String
}
// Story is a PLAIN aggregate we assemble — NOT @Generable — so we never depend on a
// @Guide array-count *range* (which Apple does not appear to support; only exact
// @Guide(.count(n)) and numeric .range(a...b) exist). Page count is controlled in app logic:
// generate one StoryPage per respond() call, carrying a short running summary, until a stop
// condition. On exceededContextWindowSize, restart the session from the summary.
```
- Use `SystemLanguageModel.contextSize` + `tokenCount(for:)` *(iOS 26.4, back-deployed —
  verify at GM)* to budget; set `GenerationOptions.maximumResponseTokens` conservatively per
  page.
- `session.prewarm()` when the authoring screen opens, to hide model load latency.

### Templates + parent custom content
- **Templates as `instructions`:** fixed tone, reading level, page count, and a
  non-negotiable rule — *always end calm and reassuring for sleep*.
- **Per-request `prompt`:** personalization (child name, age band, theme, favorites). Inject
  names/pets deterministically (templating or a `Tool`), not by hoping the model echoes them.
- **`GenerationOptions`:** temperature ~0.7–0.9 for gentle nightly variety; a **fixed-seed**
  option so a child can re-hear an identical favorite.
- **Parent-written / recorded stories** bypass the model entirely (verbatim text → TTS),
  still behind the approval gate. This path is the backbone of the degraded tier.

### Child safety / parental approval (the load-bearing control)
Apple's built-in guardrails (`guardrailViolation` / `refusal`; binding Acceptable Use
Requirements) are a **legal floor, not an age-appropriateness guarantee.** WhisperTales adds:
1. **Allow-listed, age-banded themes** constrain `instructions` and any `@Guide(.anyOf([...]))`
   theme field; a disallowed-topics blocklist is injected into `instructions`.
2. **Mandatory human review-and-approve gate** — *no* generated or custom story reaches the
   narration stage until the parent reads the full text and explicitly approves. Approved
   stories persist so they replay without regeneration. **This human gate is the safety
   mechanism** (an automated content rater is deferred to §15 as a convenience, not a v1
   control — with mandatory human approval it would be redundant belt-and-suspenders).
3. **Origin labeling is the default:** the approval screen tags each story's origin
   (`.generated` / `.parentWritten` / `.remixed`, already in the data model) so the parent
   always sees AI authorship — independent of the unresolved legal-disclosure question (§15).
4. **Errors never reach a child:** on `guardrailViolation` / `refusal`, silently regenerate
   with a safer prompt or fall back to a pre-written, author-vetted story; `Refusal.explanation`
   is parent-facing diagnostics only.

### Approval UX for the realistic (tired) parent
Reading a full multi-page story every night is enough friction that parents will stop
generating or rubber-stamp. So: surface flagged phrases with **jump-to-flag**; allow a
**trusted template** whose low-variance nightly regenerations auto-approve **only while the
content stays within the allow-list/blocklist** (any blocklist hit forces manual review);
and support **approve-from-notification earlier in the day** rather than at bedtime.

---

## 7. Data Model & Persistence

### Store
**SwiftData**, primary and sole store; `@Model` types are the domain entities (no parallel
value-type graph, no mapper layer). Core Data is the documented escape hatch (shared SQLite
format). **Large binaries are never stored in SwiftData** (not `Data`, not
`@Attribute(.externalStorage)`) — we need explicit location control, CryptoKit encryption,
and cryptographic delete-by-key.

### Entities
```swift
@Model final class ChildProfile {
    @Attribute(.unique) var id: UUID
    var name: String
    var birthdate: Date?
    var ageBand: AgeBand                 // aligned to Apple's Kids bands — see §9
    var avatarRef: String?              // small image (externalStorage OK here)
    var createdAt: Date
    @Relationship var stories: [Story]
    @Relationship var history: [PlaybackHistory]
}

@Model final class VoiceProfile {        // typically a parent ("Mom", "Dad")
    @Attribute(.unique) var id: UUID
    var label: String
    var createdAt: Date
    var modelArtifactRef: String         // relative path → encrypted clone artifact
    var sampleAudioRef: String           // relative path → encrypted reference sample
    var status: VoiceProfileStatus       // .training / .ready / .failed
    var encryptionKeyTag: String         // Keychain tag
}

@Model final class Story {
    @Attribute(.unique) var id: UUID
    var title: String
    var prompt: String
    var origin: StoryOrigin              // .generated / .parentWritten / .remixed
    var approvalState: ApprovalState     // .draft / .approved / .rejected
    var renderState: RenderState         // .none / .rendering / .ready  (drives library tile)
    var createdAt: Date
    @Relationship var childProfile: ChildProfile?
    @Relationship var voiceProfile: VoiceProfile?
    @Relationship(deleteRule: .cascade) var segments: [StorySegment]
}

@Model final class StorySegment {
    @Attribute(.unique) var id: UUID
    var index: Int
    var text: String
    var durationSeconds: Double?
    @Relationship var audioAsset: AudioAsset?
}

@Model final class AudioAsset {
    @Attribute(.unique) var id: UUID
    var fileRef: String
    var byteSize: Int
    var sampleRate: Int
    var format: String
    var sha256: String
    var encryptionKeyTag: String
}

@Model final class PlaybackHistory {
    @Attribute(.unique) var id: UUID
    var playedAt: Date
    var completed: Bool
    var positionSeconds: Double          // drives resume-from-position (§9)
    @Relationship var story: Story?
    @Relationship var childProfile: ChildProfile?
}
```

### File layout (outside the DB)
```
Library/Application Support/WhisperTales/
├── db/      → SwiftData store (default.store + -wal + -shm — ALL get file protection)
├── audio/   → per-segment narrated audio (AES-GCM encrypted)   [isExcludedFromBackup = true]
└── voices/  → cloned-voice artifacts + reference samples (encrypted) [isExcludedFromBackup = true]
```
`ModelConfiguration` points at `db/` with `cloudKitDatabase: .none`. Bundled model weights
ship in the **app bundle**, not Application Support (§10).

---

## 8. Privacy & Security

### Threat model (stated explicitly, so claims aren't read as stronger than they are)
We defend against: a **lost/stolen powered-off or logged-out** device, casual access, and
accidental data exfiltration / phone-home. We do **not** claim to defend against: an attacker
with the device **unlocked and logged in**, a malicious co-resident process running as the
user, or forensic NAND extraction. Several guarantees below are scoped to that model.

### Zero-network stance (and its honest caveats)
- No analytics SDKs, no accounts, no server, `cloudKitDatabase: .none`, no Network/Multicast
  entitlement. **But absence of an entitlement does not prevent outbound sockets** — so
  enforcement is a **runtime egress sentinel** (`NetworkSentinel`, §4.8) plus an
  **egress-blocked CI run** (§12), not entitlement inspection.
- **TTS weights are bundled and loaded by local file URL** — *never* `fromPretrained(repoID)`,
  which is a Hugging Face download. Offline-from-first-launch holds **only once the
  bundled-path loader is proven in Stage 0**; until then it is a goal, not a fact.
- **STT locale models** are not app-bundleable; they install once via `AssetInventory`. The
  *payload* is content-free, but **the network event itself exposes standard metadata** (IP,
  OS/App-Store identifiers, requested locale, timing) to Apple's CDN — it is **not** "no data
  leaves the device." The app cannot suppress this; fully air-gapped users must rely on MDM
  pre-provisioning (open question, §15) or accept STT being unavailable.
- Foundation Models runs on-device; PCC is never invoked.

### Encryption at rest (scoped honestly)
1. **NSFileProtection.** `.complete` on `audio/` and `voices/` and on **all three** SwiftData
   files (`default.store`, `-wal`, `-shm`; the WAL/SHM siblings hold unflushed plaintext).
   `.completeUnlessOpen` for files being written during background renders.
2. **CryptoKit envelope encryption.** `AES.GCM.seal` per asset with a 256-bit `SymmetricKey`;
   store `combined` on disk. **What this actually buys:** cryptographic erasure, and
   protection when the device is **powered off / logged out / on a non-boot volume.** It does
   **NOT** add at-rest strength against an **unlocked, logged-in** Mac, because the data key
   sits in the login keychain — decryptable in exactly that window. Real protection for that
   case is **FileVault + account security**, outside the app's control.
3. **macOS FileVault check.** On macOS, detect FileVault state and **warn the parent during
   onboarding if it is off**, since the encrypted blobs and keychain are then protected only
   by the hardware UID on a running machine.
4. **Key custody.** Keychain `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (excluded from
   iCloud Keychain and backups). `audio/` and `voices/` set `isExcludedFromBackup = true` so
   ciphertext doesn't ride along in device backups — making §1's "nothing leaves the device"
   literally true rather than "only encrypted."

### Parental gate (corrected for shared devices)
The product's core case is a **shared** family iPad/iPhone, where the child knows the device
passcode. So `LAContext.evaluatePolicy(.deviceOwnerAuthentication)` alone is "anyone who can
unlock the device," not "the parent." Therefore:
- **Destructive / sensitive actions** (record or overwrite a voice profile, manage child
  profiles, delete data) require a **separate app-level parent PIN** distinct from the device
  passcode — knowing the device passcode is not sufficient.
- Biometrics are offered for convenience with the **app PIN as the recovery/anti-lockout
  path** (not the device passcode).
- The child surface stays **un-gated** but read-only over **already-approved** content.

This Kids-style gate is a deliberate adult gesture; it is **not** legal parental consent
(App Review 5.1.4) and is distinct from any declared age range, which only defaults
child-vs-parent mode.

### Secure deletion — precise boundary
Apps cannot overwrite NAND (wear-leveling/FTL). "Secure delete" = **cryptographic erasure**,
and it covers **only the encrypted audio/voice files**: on delete we remove the file, delete
the row, and **delete the Keychain key** (`SecItemDelete`) — with the key gone the ciphertext
is irrecoverable. **Plaintext metadata** (child names, birthdates, prompts, story text) lives
in SwiftData/SQLite rows protected by NSFileProtection only — key destruction does nothing to
it, and deleted rows can linger in WAL/free pages. So on child- or voice-profile deletion we
also run a **SQLite `VACUUM` / store rewrite** (and `PRAGMA secure_delete` where applicable).
Product copy says **cryptographic erasure**, never "DoD wipe." (COPPA-adjacent claims get
legal review — §15.)

### Runtime plaintext hygiene
- **No decrypt-to-temp** for voice artifacts — decrypt in memory. If MLX requires
  memory-mapping weight files (which conflicts with whole-file encryption), resolve the
  scheme in Stage 0 (encrypted-mmap or in-memory decrypt) before relying on it (§15).
- Raw mic capture is written straight to a `.complete`-protected location and encrypted
  immediately; the plaintext intermediate is removed.
- Suppress story text from the app switcher snapshot in the parent area; no pasteboard auto-copy.

### Provenance watermark (so a reviewer doesn't mistake it for tracking)
Narrated audio carries the model's inaudible **PerTh** provenance watermark. It is computed
and embedded **entirely on-device**, contains **no identifier and no network callback**, and
exists for synthetic-media provenance only. We retain it (removal violates the license); it
does not weaken the offline guarantee.

### Dependency audit
Pin `mlx-audio-swift` to a commit and **audit its dependency tree** (it pulls `mlx-swift` and
Hugging Face Hub client code) for any analytics / telemetry / download paths — that is the
usual way a "no analytics" claim silently breaks.

---

## 9. User Experience & Key Flows

Two modes: **Child Playback** (default, un-gated, bedtime-friendly) and **Parent/Admin**
(gated, §8). Many target children are **pre-readers**, so the child surface is **audio-first
and icon-first** — operable with zero reading.

### Kids-Category & age bands — a product decision, not an open question
Apple's Kids Category has exactly three bands: **5 & under / 6–8 / 9–11**; 12-year-olds fall
**outside** it. WhisperTales **targets the Kids Category** and aligns its internal bands to
**5&under / 6–8 / 9–11**, accepting its parental-gate and no-tracking obligations. (If a
broader 12+ reach is wanted, that is a separate non-Kids-Category build with a different
privacy posture — explicitly out of v1.) This choice flows into onboarding and content-safety
prompts.

### Onboarding / voice training (parent, gated)
1. Parental gate (app PIN / biometric).
2. Brief **voice-cloning consent/explainer** copy (what cloning your voice means, where it
   stays).
3. One-time STT language-pack install (disclosed) if needed.
4. Record ~30 s reading a provided script; auto-trim best ~10 s; **quality gate**
   (length/SNR/clipping) with retry guidance ("a bit too quiet — move closer to the mic").
5. **Preview your voice (acceptance step):** synthesize one sample sentence in the new clone;
   the parent listens and **accepts or re-records** before the profile goes live (tied to the
   §12 identity-match rubric — the parent, not just QA, gates quality). The first time a
   parent hears the clone must not be the child's bedtime.
6. A **re-record / replace voice** path lives in parent data-management (voices change; a bad
   clone must not be permanent).

### Parent authoring (gated)
Pick child + voice + age band + allow-listed theme → generate a paged story, **or** dictate
(DictationTranscriber) / type a custom story, **or** "remix my story." **Review & approve**
(jump-to-flag, origin label) → narration renders **now, ahead of bedtime** on the serial
queue (progress shown). Only fully-rendered, approved stories appear in the child library.

### Child playback (default, bedtime-friendly)
- **Active-child picker:** large **avatar** selector at the un-gated surface (no auth); the
  library filters to **that child's** approved stories and intended **voice** (serves the
  multi-child / separated-parent / military premise — which parent a given child hears).
- **Dark, low-stimulation UI**, few oversized targets, minimal text; story tiles identifiable
  by **illustration** with an optional **spoken title in the parent's voice** on focus.
- **Empty-library first run:** a child handed the device on night one sees a gentle,
  illustrated "ask a grown-up to make your first story" (spoken), never a blank grid.
- **Player controls — minimal but complete:** large **play/pause**, a single **"play again
  from the start,"** and **resume-from-last-position** on reopen (wired to
  `PlaybackHistory.positionSeconds`). No child-facing scrubbing. (Recommend a single "again"
  over per-page navigation.)
- **Now Playing / Control Center policy (first-class requirement):** because `.playback`
  background audio auto-populates the lock screen, register `MPRemoteCommandCenter` and
  **disable** `changePlaybackPositionCommand`, `next/previousTrack`, and seek; expose **at
  most play/pause**; set neutral `MPNowPlayingInfoCenter` metadata. A child poking the lock
  screen cannot scrub or skip. (UI test asserts this.)
- **Sleep timer / lights-out:** fades and stops **at a sentence/page boundary**, not a hard
  cut. Define both edges: if narration **ends before** the timer → silence (optional gentle
  ambient/white-noise continuation, configurable); if the timer **fires mid-story** → graceful
  fade at the next boundary. Background audio via `.playback` keeps it playing when the screen
  sleeps.
- **Voice-request interaction (robust, not happy-path):** child taps a clearly-marked button
  and speaks. Given **unverified child-voice STT accuracy** (§12), this is **never the only
  way** to start a story — a tappable **picture grid** is always available. The flow:
  fuzzy/keyword match over approved titles/themes (not exact string) → **audible confirmation
  in the parent's voice** ("Want to hear *The Brave Little Fox*?") → play. No-match /
  low-confidence / silence → gently offer a recently-loved story rather than dead-ending;
  retries capped. **No on-the-fly unapproved generation ever reaches a child.**
- **Bedtime parental controls (beyond the sleep timer):** a **stories-per-session** cap
  and/or **time-of-day auto-stop** ("one story, then lights out").

### Interruptions
Handle `AVAudioSession` interruptions (incoming call, alarm) from the child's standpoint:
pause cleanly and **auto-resume** the bedtime story where possible, or stop gracefully — never
drop into a confusing silent state.

### Accessibility
Parent mode: Dynamic Type, full VoiceOver, large targets, high-contrast dark theme, Reduced
Motion, declared Accessibility Nutrition Labels (Dark Interface, Reduced Motion). Child mode:
**pre-reader** path — image/icon navigation, spoken titles and spoken fallback messages
("ask a grown-up") so a 3–5-year-old never needs to read.

---

## 10. Model & Asset Strategy

> **All sizes and licenses below are UNVERIFIED and are Stage-0 deliverables.** Do not treat
> any megabyte figure or license as settled until Stage 0 confirms it against the pinned
> commit and the exact Hugging Face repo.

### The model-selection decision (Stage 0)
The package's **documented** TTS models are: **Qwen3-TTS, Fish Audio S2 Pro, Soprano,
VyvoTTS, Orpheus, MOSS-TTS, Marvis, Pocket TTS, Irodori TTS**. Chatterbox is **not** in the
Swift README. So model choice is a **Stage-0 decision**, made by this procedure:
1. **API-existence gate:** clone the pinned `mlx-audio-swift` commit and confirm a
   **reference-audio cloning entry point actually ships** (grep for a `refAudio`/`refText`
   parameter; confirm `GenerateParameters` and the generate signature).
2. **Pick from models that (a) ship a Swift cloning path, (b) carry a confirmed
   commercial-OK license on the exact repack we bundle, and (c) pass the §12 voice rubric on
   real hardware within the §2 peak-RSS ceiling.** **Qwen3-TTS** (in-package, cloning-capable,
   Apache-2.0 upstream) is the leading candidate; **Marvis** (Apache-2.0) is a backup.
3. **Fish Audio S2 Pro is hard-excluded — non-commercial license. Never ship it.** (No
   runtime "registry guard" needed; we simply don't import it.)

### If no Swift cloning path exists (named fallback)
If Stage 0 finds the Swift package ships **no** reference-audio cloning, the realistic
options, with the **default in bold**, are:
- **(default) Use a model whose Swift cloning IS documented** (re-run step 2 across the list).
- Wrap the Python `mlx-audio` cloning path via a **local helper process** (macOS-friendly;
  heavier on iOS) — changes the architecture, so only if no Swift path exists at all.
- Port the Python cloning path to Swift — large, and beyond a first Swift project; last resort.

### Candidate asset table (verify every cell in Stage 0)
| Asset | Source | License status | Embedding |
|---|---|---|---|
| **STT locale models** | Apple `AssetInventory` | Apple SDK/OS | **Not bundleable**; one-time on-device install; disclosed. Zero app-size impact. |
| **TTS cloning model (chosen in Stage 0)** | `mlx-audio-swift` / HF repack | **MUST be confirmed per exact repack** — undeclared-license repacks are **ship-blockers** | **Bundle, local-URL load.** Prefer a repack with an explicit Apache-2.0/MIT license file; otherwise re-quantize from a clearly-licensed source and embed the license in `Resources/`. |
| **Story text — AFM on-device** | Apple `FoundationModels` | Apple SDK/OS | OS-provided; not bundled, not downloaded by us. |

> **Licensing reality check (from Stage-0 research):** several `mlx-community` quantized
> repacks (e.g. the Chatterbox **turbo** 4-bit/8-bit) currently declare **no license field** —
> only some fp16 repacks declare Apache-2.0. An undeclared-license model in a paid kids' app
> is a **ship-blocker**, not a footnote. Resolve before bundling.

### Sizes & budgets (corrected, still verify)
- Verified-ish on-disk magnitudes were ~**2× larger** than first assumed (e.g. a turbo-4bit
  repack ≈ **~814 MB**, turbo-8bit ≈ **~965 MB**, regular-4bit ≈ **~1.0 GB**). Treat these as
  *order-of-magnitude*; measure the chosen model in Stage 0.
- **iOS app-size ceiling:** keep the full payload (TTS weights + codecs + app + STT runtime)
  under the iOS uncompressed-app limit. **Do not use On-Demand Resources** (deprecated as of
  iOS 27); a deferred variant would mean Background Assets — a network download that breaks
  strict-offline for whatever it delivers.
- **macOS:** bundle the larger/higher-precision weights; Developer-ID-signed + notarized +
  stapled DMG → genuinely never touches the network for models.
- **Peak RSS** (synthesis working set) is the real iOS cliff — a separate, hard Stage-0
  go/no-go from on-disk size (§2).

### Model updates post-launch
With no ODR, **every weights improvement is a full app update** (~hundreds of MB to ~1 GB).
State this explicitly as a release-process constraint; pin a known-good commit/tag once Stage 0
confirms a working revision.

---

## 11. Error Handling & Resilience

Fail fast with descriptive **parent-facing** messages; **never** surface raw model errors to
a child.

| Failure mode | Detection | Response |
|---|---|---|
| **Bad reference audio** | quality gate (length/SNR/clipping) | Block profile creation; specific retry guidance; never silently produce a poor clone. |
| **Cloning API absent in package** | Stage-0 API-existence gate | Trigger the §10 fallback decision before building further. |
| **Synthesis failure / OOM** | stream error; jetsam | Retry once on the serial queue; if memory-driven, surface "this device is low on memory," keep already-rendered segments. |
| **Story guardrail / refusal** | `GenerationError.guardrailViolation` / `.refusal` | Silently regenerate safer, else fall back to a pre-written story. Child never sees it. |
| **Context window exceeded** | `GenerationError.exceededContextWindowSize` | Restart session from the running summary; continue page-by-page. |
| **Foundation Models unavailable / AI disabled / region-gated** | `availability != .available` | Drop to the **degraded tier** (parent-written/recorded only); clear, non-blocking explainer. |
| **STT hardware unsupported** | `SpeechTranscriber.supportsDevice() == false` | Use `DictationTranscriber` where applicable; otherwise disable the affected STT feature. |
| **STT locale not installed / offline** | `installedLocales` check | Prompt one-time install; if offline, disable STT features with explanation; rest of app works. |
| **Live STT session left hanging** | `defer finalizeAndFinishThroughEndOfInput()` | Guarantee session finish on every live-mic path. |
| **Story not yet rendered at play time** | `Story.renderState != .ready` | Library shows "still preparing" tile; child can't open it; never a lazy at-play render. |
| **Playback interruption (call/alarm)** | `AVAudioSession` interruption | Pause; auto-resume where possible, else graceful stop. |
| **Low storage** | pre-flight free-space check | Warn before generating; offer to delete old stories (cryptographic erase + VACUUM). |
| **Parental gate fails / unavailable** | `LAContext` result | App-PIN fallback (not device passcode); never lock the parent out. |
| **Key missing / decryption fails** | `AES.GCM.open` throws | Treat asset as lost; honest message; allow re-narration from stored text. |
| **Unexpected outbound socket** | `NetworkSentinel` (debug/CI) | **Fail the run** — offline-guarantee regression. |

---

## 12. Testing Strategy

### Unit (services + workflows, protocol fakes)
- Workflows tested against **in-memory fakes** of the seamed protocols
  (`FakeVoiceSynthesizing`, `FakeStoryTextService`, `FakeSpeechService`, `FakeStoryStore`,
  `FakeKeyStore`). Tests describe **behavior**: "an unapproved story is never narrated,"
  "deleting a VoiceProfile destroys its Keychain key and VACUUMs metadata,"
  "a `.rendering` story is not child-openable."
- SwiftData via in-memory `ModelConfiguration(isStoredInMemoryOnly: true)`.
- CryptoKit round-trip: seal→open equality; **delete-key→open-fails** (cryptographic-erasure
  proof).

### Offline-guarantee enforcement (hard gate, not a hedge)
- **Egress-blocked CI run:** block all network egress and assert **every** inference path
  (cloning, narration, generation, file STT) still succeeds. Any outbound connection — except
  the explicitly allow-listed, user-initiated `AssetInventory` install — is a **test
  failure**. `NetworkSentinel` enforces the same at runtime in debug.

### Snapshot / UI
- SwiftUI snapshots: Child Player (dark, large targets), Library (`@Query`), Review-&-Approve,
  Onboarding quality-gate + voice-preview states.
- UI tests: parental gate (gated screens unreachable without app PIN; biometric→PIN recovery);
  **lock-screen remote-command policy asserts scrubbing/skip disabled**.

### Manual voice-quality rubric (real device — MLX can't run in Simulator)
Scored 1–5 each; pass threshold agreed in **Stage 0** and reused as the onboarding
voice-preview bar:
1. **Identity match** — does it sound like the parent? 2. **Naturalness / prosody** — gentle
bedtime cadence? 3. **Intelligibility** — every word clear for a child? 4. **Artifacts** —
glitches/robotic tones/clipping? 5. **Child-voice STT accuracy** — does the chosen module
capture a 3–11-year-old's spoken request? (Apple publishes none; measure empirically.)

### CI reality for the ML path
MLX needs hardware. Decide and document: a **self-hosted Apple-Silicon CI runner** for the
inference suite, or a **named manual-on-device gate** before each release. Don't pretend
hosted CI covers it.

---

## 13. Project Structure

Single **SwiftUI multiplatform** target (native AppKit-backed on Mac — **not** Mac Catalyst).
The one platform seam is a **protocol with two implementations chosen at the composition
root** (`AppDependencies`), not `#if os(...)` inside service bodies.

```
WhisperTales/                      (Xcode project / SwiftPM)
├── WhisperTalesApp.swift          @main — builds AppDependencies, the DI composition root
├── App/
│   ├── AppDependencies.swift      struct: constructs the object graph once (init injection)
│   └── RootView.swift             mode routing (Child default / Parent gated); env injection
├── Presentation/
│   ├── Child/                     ActiveChildPicker, LibraryView(@Query), BedtimePlayerView,
│   │                             VoiceRequestView (+ picture grid)
│   ├── Parent/                    OnboardingView, VoicePreviewView, AuthoringView,
│   │                             ReviewApproveView, ProfilesView, DataManagementView
│   └── Common/                    ParentalGateView, theming, components
├── Workflows/                     TrainVoiceUseCase, GenerateStoryUseCase, NarrateStoryUseCase
├── Services/
│   ├── Speech/                    AppleSpeechService (actor)
│   ├── Voice/                     MLXVoiceSynthesisService (actor), VoiceQualityAssessor
│   ├── Story/                     FoundationModelStoryService (actor)
│   ├── Audio/                     AudioCapture, AudioPlaybackEngine,
│   │                             AudioSessionController (protocol + iOS/macOS impls),
│   │                             NowPlayingController
│   ├── Persistence/              StoryStore (repo) + @Model definitions
│   ├── Storage/                   AudioFileStore, ModelAssetStore (protocol + iOS/macOS impls)
│   ├── Security/                  KeyStore, ParentalGate, FileVaultCheck (macOS)
│   └── Net/                       NetworkSentinel
└── Tests/
    ├── WorkflowTests/             protocol-fake behavior tests
    ├── ServiceTests/              SwiftData in-memory, CryptoKit round-trips, egress-blocked
    └── UITests/                   gate flow, lock-screen command policy, snapshots
```
**SwiftPM:** `https://github.com/Blaizzy/mlx-audio-swift.git` — import `MLXAudioTTS`,
`MLXAudioCore`, **`MLXAudioCodecs`** (reference-audio decode); transitively `mlx-swift`. Pin a
commit (chosen in Stage 0) and **audit the dependency tree** (§8).

---

## 14. Staged Implementation Plan

Each stage: **Goal / Success Criteria / Tests / Status.** Stage 0 is split so the
Apple-toolchain learning curve is isolated from the MLX-cloning question — critical for a
first-time Swift developer on beta tooling.

### Stage 0a — Swift / Xcode / device smoke test (NO MLX)
**Goal:** Stand up a 1-screen SwiftUI app that records mic audio and plays it back **on a
physical device** — exercising signing, provisioning, device trust, `AVAudioSession`, capture
and playback — with zero ML.
**Success Criteria:** Record → play back on a real iPhone *and* a Mac; a known-good
capture/playback harness exists to feed Stage 0b.
**Tests:** Manual on-device; basic capture/playback unit coverage.
**Status:** Not Started

### Stage 0b — Cloning de-risking spike (the #1 risk)
**Goal:** Settle whether `mlx-audio-swift` performs **reference-audio cloning** acceptably on
iOS hardware, fully offline.
**Success Criteria (in order):**
1. **API-existence gate** — the pinned commit ships a reference-audio cloning entry point
   (confirmed by reading the source), and a **bundled-local-URL** loader works with **no
   network call** (`NetworkSentinel` clean).
2. Using the §10 procedure, a chosen model clones a ~10 s reference and synthesizes a sentence
   that scores **≥ the agreed §12 rubric threshold** on a real iPhone and Mac.
3. **Peak RSS < the §2 ceiling** on an 8 GB device; real-time factor measured and a
   batch-render latency estimate for a full story produced.
4. The chosen model's exact repack carries a **confirmed commercial-OK license.**
**Tests:** Voice rubric; egress-blocked check; memory/RTF measurement.
**Status:** Not Started
> If any gate fails, execute the §10 fallback (default: pick a different in-package model)
> **before** building further.

### Stage 1 — Persistence, security, parental gate
**Goal:** SwiftData graph + encrypted file storage + Keychain keys + app-PIN/biometric gate +
egress sentinel.
**Success Criteria:** CRUD `VoiceProfile`/`Story`; AES-GCM files with `.complete` on
store+WAL+SHM and `isExcludedFromBackup` on blobs; delete destroys key **and** VACUUMs
metadata (decryption then fails); parent area unreachable without the app PIN; macOS FileVault
check warns when off; `NetworkSentinel` active.
**Tests:** in-memory CRUD; seal/open + delete-key proof; gate + PIN-recovery UI test;
egress-blocked run.
**Status:** Not Started

### Stage 2 — STT input path
**Goal:** Parent dictation (`DictationTranscriber`), child command (`SpeechTranscriber`), file
transcription, with `supportsDevice()` gating + locale install.
**Success Criteria:** mic → `AVAudioConverter` → `AnalyzerInput` → live interim results;
correct module per use case; one-time locale install; sessions always finalized.
**Tests:** fake-service workflow tests; on-device smoke; child-voice accuracy sampling (rubric 5).
**Status:** Not Started

### Stage 3 — Story generation + safety/approval
**Goal:** Foundation Models **page-by-page** generation + mandatory human review-&-approve +
origin labeling + degraded-tier fallback.
**Success Criteria:** generate within the 4K budget (page-by-page summarization); **no story
narrates without explicit approval**; AI origin shown; graceful degrade when AFM unavailable
or AI disabled.
**Tests:** "unapproved never narrated"; guardrail/refusal → regenerate/fallback;
context-exceeded → resume; availability-gating.
**Status:** Not Started

### Stage 4 — Narration pipeline + playback
**Goal:** Approved text → cloned-voice narration (in-memory serial queue, **rendered at
approval time**) → encrypted store → bedtime player with locked-down remote commands, sleep
timer, resume, and interruption handling.
**Success Criteria:** approve → render → ready tile → child plays in parent's voice; resume
from `positionSeconds`; "play again"; sleep timer fades at a boundary; lock-screen scrubbing/
skip disabled; call/alarm interruption handled; cancellation works.
**Tests:** on-device integration; resume/replay; sleep-timer edges; remote-command-policy UI
test; `Task.isCancelled`; low-storage pre-flight.
**Status:** Not Started

### Stage 5 — Child UX, voice requests, accessibility, hardening
**Goal:** Active-child picker + per-child filtered library, robust voice-request flow with
picture-grid alternative, empty-library night-one, pre-reader accessibility, bedtime parental
controls, full §11 matrix.
**Success Criteria:** per-child scoping; voice request → fuzzy match → audible confirm, with
no-match/silence handled and a tappable alternative always present; pre-reader audio-first
nav; stories-per-session / time limit; Dynamic Type/VoiceOver pass.
**Tests:** snapshots; VoiceOver/pre-reader flow; error-matrix coverage.
**Status:** Not Started

### Stage 6 — Packaging & distribution (**GM-gated**)
**Goal:** iOS bundled-quantized offline build under the size ceiling; macOS notarized stapled
DMG. **External dependency: Xcode 27 / iOS 26 / macOS 26 GM** (no beta-SDK App Store
submission).
**Success Criteria:** iOS installs and runs cloning/narration **offline from first launch**
under the ceiling; macOS DMG signed + notarized + stapled, offline for models; **all
Speech/FoundationModels/mlx-audio signatures re-verified against GM headers.**
**Tests:** offline first-launch on a fresh device; size + peak-RSS budgets; Gatekeeper/
notarization validation; egress-blocked acceptance.
**Status:** Not Started

---

## 15. Open Questions & Risks

### Highest-priority / potentially blocking
- **Does `mlx-audio-swift` actually ship a reference-audio cloning API on iOS?** The Swift
  README lists preset voices and does **not** mention Chatterbox or a `refAudio`/`refText`
  path; Python `mlx-audio` documents reference-audio cloning for *other* models. **Confidence:
  unverified / possibly absent.** Stage 0b's first gate settles it; §10 names the fallback.
- **Repack licensing.** The exact quantized repack we bundle **must** carry a confirmed
  commercial-OK license. Some `mlx-community` repacks declare **none** — a ship-blocker. Fish
  Audio S2 Pro is non-commercial: excluded.
- **iOS peak memory during synthesis** on an 8 GB device is the real cliff (separate from
  on-disk size). Hard Stage-0 go/no-go.
- **First-Swift-app + Xcode-27-beta.** New language, new platform, beta SDK with evolving APIs
  (`AnalyzerInput` shape, `contextSize`/`tokenCount` in 26.4, etc.). Mitigations: Stage 0a
  isolates the toolchain; pin the SDK; re-verify every signature at GM (Stage 6); **no
  commercial submission before GM.**

### API names to confirm against the pinned commit / GM headers
- `mlx-audio-swift`: the generate signature + `GenerateParameters`, the reference-audio symbol,
  `MLXAudioCodecs` WAV→`MLXArray` loader, the stream event cases behind `SynthesizedChunk`, and
  the package's `Package.swift` Swift-tools/platform minimums.
- Speech: `SpeechTranscriber.supportsDevice()` device set; exact preset names
  (`.progressiveLiveTranscription` / `.offlineTranscription` / time-indexed variants);
  `AssetInventory.Status` cases; `SpeechAnalyzer.Options` retention semantics.
- FoundationModels: the `availability` enum shape; `@Guide` supports exact `.count(n)` and
  numeric `.range(...)` only (no array-count *range* — page count stays in app logic);
  whether the larger model variant keeps the 4,096-token window on capable devices.

### Privacy / security to resolve
- **Egress enforcement** is the single most important control — `NetworkSentinel` + egress-
  blocked CI must be in from Stage 1; audit the `mlx-swift` / HF-Hub dependency tree.
- **macOS at-rest** depends on FileVault (outside app control) — require the check + warning.
- **MLX weight mmap vs whole-file encryption:** confirm in Stage 0 we can avoid decrypt-to-temp.
- **Air-gapped STT:** locale models aren't bundleable; whether MDM/managed provisioning can
  pre-install them for no-connectivity (military) users is open.

### Compliance (legal review before commercial ship)
- Whether Apple accepts a **voice-clone app in the Kids Category**, and the consequences of the
  3–11 band choice (12-year-olds excluded).
- Whether AI-generated story text needs parent-facing disclosure (we default to origin
  labeling regardless); AUP forbids removing watermarks/content credentials.
- "Cryptographic erasure" / "encryption" marketing claims for a COPPA-adjacent kids app — get
  sign-off; claim only what §8 actually delivers.

### Deferred to a later version (explicit cut line)
Swappable model registry; persisted/durable synthesis queue; automated second-pass content
rater; Secure Enclave key-wrapping; multi-language narration; iCloud/family sharing; a
non-Kids-Category 12+ build.
