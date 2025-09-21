#!/bin/bash
set -euo pipefail

# Quick test script to validate installer logic
echo "Testing installer components..."

# Test 1: Check if we can install git
echo "Test 1: Installing git..."
if pacman -Sy --noconfirm git; then
    echo "✅ Git installation works"
else
    echo "❌ Git installation failed"
    exit 1
fi

# Test 2: Check if git clone works
echo "Test 2: Testing git clone..."
cd /tmp
rm -rf lobby-kiosk-test
if git clone https://github.com/kenzie/lobby-kiosk.git lobby-kiosk-test; then
    echo "✅ Git clone works"
    ls -la lobby-kiosk-test/
else
    echo "❌ Git clone failed"
    exit 1
fi

# Test 3: Check if config files exist
echo "Test 3: Checking config files..."
if [[ -f lobby-kiosk-test/configs/systemd/lobby-kiosk.target ]]; then
    echo "✅ Config files found"
else
    echo "❌ Config files missing"
    exit 1
fi

echo "🎉 All tests passed! Installer should work."
rm -rf lobby-kiosk-test