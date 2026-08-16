#!/bin/bash
# Build the OCR helper binary for window_translator.lua
set -e
cd "$(dirname "$0")"
swiftc -O ocr_helper.swift -o ocr_helper \
    -framework Vision \
    -framework AppKit \
    -framework Foundation
echo "Built: $(pwd)/ocr_helper"
