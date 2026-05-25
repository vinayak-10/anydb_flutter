# AnyDb Branding & System Overhaul Tasks

## Completed Branding & Asset Deployment
- `[x]` Refine logo concepts based on classical Indian heritage & modern minimalist aesthetics.
- `[x]` Generate 7 production-grade, infinitely scalable Vector SVG files under [assets/logo_concepts/](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/assets/logo_concepts/).
- `[x]` Design the new **Yantra-Prism Hybrid** superposition concept as a standard-compliant Vector SVG [anydb_logo_yantra_prism.svg](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/assets/logo_concepts/anydb_logo_yantra_prism.svg).
- `[x]` Build the automated Pillow-based PNG generator script [generate_hybrid.py](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/assets/generate_hybrid.py) to draw the high-fidelity superposition logo directly.
- `[x]` Develop Pillow-based conversion script `assets/convert.py` to translate JPEG binary streams into standard-compliant PNGs.
- `[x]` Integrate SVG logo into both drawer states (anonymous and logged-in headers) in [drawer_content.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/components/drawer_content.dart).
- `[x]` Auto-resize and deploy high-fidelity `ic_launcher.png` assets across all 5 Android resource mipmap subdirectories under [android/app/src/main/res/](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/android/app/src/main/res/) to replace the launcher/app home screen icons.
- `[x]` User selection of active official logo concept (Yantra-Prism Hybrid SVG) integrated directly as a vector asset without PNG color shift.

## Execution of System Improvements
- `[x]` Refactor congested TabBar in `collection_view.dart` with dynamic `isScrollable` and custom label padding.
- `[x]` Configure premium orange theme seed color `Color(0xFFE9967A)` in `main.dart` and enforce clean white Scaffold, dialog, and drawer backgrounds.
- `[x]` Update `drawer_content.dart` to inherit primary theme colors for headers and set drawer background explicitly to white.
- `[x]` Implement robust accounting bounds checking in `simple_account.dart` to cap negative discounts.
- `[x]` Wrap text in `_SimpleAccountSummary` inside an `Expanded` widget to prevent transaction detail layout overflow.
- `[x]` Implement `_getSortTime(ElementModel e)` and stable record sorting in `element_db.dart`.
- `[x]` Update `_flatten` in `extractor_service.dart` to correctly parse and recursive-flatten dot-separated and non-colon transaction list arrays.
- `[x]` Validate implementation with `flutter analyze` and run a full `flutter clean` clean/build verification.
