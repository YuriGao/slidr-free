# Middle-click implementation provenance

## Purpose and license boundary

This record documents the engineering controls used for Slidr Free's middle-click beta. It is not legal advice and does not claim a legally strict “clean-room” process.

- Slidr Free baseline: `1246345e526190de89618ce4b301c6f34cc90e21`.
- Behavior reference: `artginzburg/MiddleClick@21234476a51d58b87c4b8d6fdd7b49ce49147c8d`.
- MiddleClick is licensed under GPL-3.0; Slidr Free is licensed under MIT.
- The implementation is an independent behavior-level reimplementation. MiddleClick is not a source or binary dependency of Slidr Free.
- If GPL source, resources, or build artifacts enter the deliverable, the MIT publication flow must stop until the licensing decision is reassessed.

## Permitted implementation inputs

Implementers were limited to:

1. The approved Slidr Free middle-click design specification.
2. Public user-visible behavior and black-box validation results.
3. Apple platform documentation.
4. Existing Slidr Free code and tests.

Implementation agents received the approved specification and the Slidr Free repository. They did not receive a MiddleClick checkout or upstream source-analysis context.

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

Each workstream was reviewed by a separate review-only role before the next workstream proceeded. Those reviews checked specification compliance, ordinary-input fail-open behavior, concurrency/lifecycle safety, test coverage, and the no-source-reuse constraint. Critical and Important findings were fixed and re-reviewed before later work began. A final whole-branch provenance/copying review remains a required pull-request and release gate.

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
