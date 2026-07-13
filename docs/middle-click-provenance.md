# Middle-click implementation provenance

## Purpose and license boundary

This record documents the engineering controls used for Slidr Free's middle-click beta. It is not legal advice and does not claim a legally strict “clean-room” process.

- Slidr Free baseline: `1246345e526190de89618ce4b301c6f34cc90e21`.
- Behavior reference: `artginzburg/MiddleClick@21234476a51d58b87c4b8d6fdd7b49ce49147c8d`.
- MiddleClick is licensed under GPL-3.0; Slidr Free is licensed under MIT.
- The implementation is an independent behavior-level reimplementation. MiddleClick is not a source or binary dependency of Slidr Free.
- If GPL source, resources, or build artifacts enter the deliverable, the MIT publication flow must stop until the licensing decision is reassessed.

The configurable 2–4-finger extension is specified by `docs/superpowers/specs/2026-07-12-configurable-middle-click-finger-count-design.md` (design commit `5189a4b`). It supersedes only the original fixed-three-finger product scope; the original concurrency, fail-open, lifecycle, and licensing controls remain in force.

The success-haptic extension is specified by `docs/superpowers/specs/2026-07-13-middle-click-haptic-feedback-design.md` (design commit `6a576f0`). It uses the public AppKit `NSHapticFeedbackManager` API and existing Slidr Free success boundaries. Its implementation inputs are the approved specification, existing Slidr Free code and tests, and Apple's SDK documentation; no upstream MiddleClick source, resource, project, binary, or implementation structure is used.

## Permitted implementation inputs

Implementers were limited to:

1. The approved Slidr Free middle-click design specification.
2. Public user-visible behavior and black-box validation results.
3. Apple platform documentation.
4. Existing Slidr Free code and tests.

For the configurable-count extension, public behavior inputs were limited to the upstream public README's “Number of Fingers” section, the public 3.2.0 release note, and the public three-finger-drag guidance. Those materials establish a single exact-count preference, the two-finger conflict warning, and four fingers as a documented way to avoid three-finger-drag conflicts. Slidr Free deliberately narrows the offered range to 2–4 fingers and independently defaults it to 4 for this product.

Implementation agents received the approved specification and the Slidr Free repository. They did not receive a MiddleClick checkout or upstream source-analysis context.

The public-behavior reviewer for the configurable extension inspected only those public documentation pages. No MiddleClick source, resources, project files, or build artifacts were opened, downloaded, or supplied to implementation work.

## Prohibited implementation inputs

The following were explicitly prohibited:

- MiddleClick source code or resources;
- MiddleClick build artifacts or binary linkage;
- adaptation of copyrightable implementation expression;
- line-by-line translation or transliteration;
- structural copying based on upstream implementation details.

Task reports record that implementation roles did not inspect or use prohibited inputs. This statement records the engineering process and is not a legal conclusion about copyright or licensing.

## Role separation and review record

Implementation was split into bounded workstreams:

- core settings migration and exact-three recognizer;
- physical-touch adaptation and edge arbitration;
- atomic session bridge and pure mouse reducer;
- Event Tap, emitter, and middle-button system action;
- lifecycle, Settings integration, and diagnostics.
- configurable-count settings migration, recognition, lifecycle propagation, UI, and bilingual documentation.
- success-haptic settings migration, public-AppKit boundary, Tap/physical success wiring, lifecycle semantics, UI, and bilingual documentation.

Each workstream was reviewed by a separate review-only role before the next workstream proceeded. Those reviews checked specification compliance, ordinary-input fail-open behavior, concurrency/lifecycle safety, test coverage, and the no-source-reuse constraint. Critical and Important findings were fixed and re-reviewed before later work began. The original integration's final whole-branch provenance/copying review is recorded in the pull request; the extension review is recorded below.

The configurable-count extension received a final read-only review over `71cb6c161de26639db4b6a2cfc509c739edb45e8..970f7f7384ffae40bc55892581e4a0d9a618a278`. The reviewer reported no Critical or Important findings after fixes, confirmed the public-document-only input boundary, and found no suspected upstream source, resource, project, binary, structural, or transliteration reuse in the extension.

The success-haptic extension received a final read-only review over `6a576f0..b4dcb19`. The reviewer reported no Critical, Important, or Minor findings after the boundary-test additions; confirmed the successful-up-only behavior, main-thread AppKit delivery, and delivery-time preference check; and found no suspected upstream source, resource, project, binary, structural, or transliteration reuse in the extension.

## Dependency inventory

Slidr Free has no external Swift package dependency and does not link MiddleClick.

Runtime/build dependencies are:

- Swift 5.9 standard library and Swift Package Manager;
- macOS 13 or later;
- Apple `Foundation`, `Combine`, `AppKit`, `SwiftUI`, `CoreGraphics`, `ApplicationServices`, and `ServiceManagement` frameworks;
- Apple's private `MultitouchSupport` framework, loaded dynamically at runtime for physical touch frames;
- project-owned source, icon, menu bar image, localizations, and MIT `LICENSE`.

The release verifier requires the root MIT license to be copied byte-for-byte to `Slidr-Free.app/Contents/Resources/LICENSE` and into the ZIP archive.

## Publication gate

Before beta publication, an independent reviewer must inspect the complete Slidr Free diff for source, resource, structural, or transliteration reuse and record the reviewed commit range and result here or in the pull request. Any suspected GPL-derived input blocks MIT publication pending maintainer and legal review.
