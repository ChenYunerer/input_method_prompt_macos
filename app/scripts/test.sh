#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
mkdir -p .build/local-tests
swiftc -parse-as-library -swift-version 5 \
    Sources/InputMethodPrompt/InputSource.swift \
    Sources/InputMethodPrompt/PromptView.swift \
    Sources/InputMethodPrompt/LoginItem.swift \
    Sources/InputMethodPrompt/Settings.swift \
    Sources/InputMethodPrompt/Overlay.swift \
    Sources/InputMethodPrompt/FullScreenIndicator.swift \
    Sources/InputMethodPrompt/MouseIndicator.swift \
    Sources/InputMethodPrompt/MouseFrameClock.swift \
    Sources/InputMethodPrompt/SelfCheck.swift \
    Tests/InputMethodPromptTests.swift \
    -framework AppKit -framework Carbon \
    -o .build/local-tests/InputMethodPromptTests
.build/local-tests/InputMethodPromptTests "$@"
