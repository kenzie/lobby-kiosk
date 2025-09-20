#!/bin/bash
set -euo pipefail

# Vue.js Application Builder - Rapid MVP
REPO_URL="https://github.com/kenzie/lobby-display.git"
RELEASE_DIR="/opt/lobby/app/releases/$(date +%Y%m%d_%H%M%S)"
CURRENT_LINK="/opt/lobby/app/current"

cd /opt/lobby

echo "Building application release: $RELEASE_DIR"

# Clone or update repository
if [[ ! -d "app/repo" ]]; then
    echo "Cloning repository..."
    git clone "$REPO_URL" app/repo
else
    echo "Updating repository..."
    cd app/repo
    git fetch origin
    git reset --hard origin/main
    cd /opt/lobby
fi

# Create new release
echo "Creating release build..."
cp -r app/repo "$RELEASE_DIR"
cd "$RELEASE_DIR"

# Build application
echo "Installing dependencies..."
npm ci --production=false

echo "Building Vue.js application..."
npm run build

# Verify build
if [[ ! -f "dist/index.html" ]]; then
    echo "Build failed: no index.html found"
    rm -rf "$RELEASE_DIR"
    exit 1
fi

# Atomic switch to new version
echo "Deploying new version..."
ln -sfn "$RELEASE_DIR" "$CURRENT_LINK.new"
mv "$CURRENT_LINK.new" "$CURRENT_LINK"

# Reload web server
sudo systemctl reload nginx

# Cleanup old releases (keep last 3)
cd /opt/lobby/app/releases
ls -1t | tail -n +4 | xargs -r rm -rf

echo "Deployment complete: $(basename $RELEASE_DIR)"