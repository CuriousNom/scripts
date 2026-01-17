cat > convert_nikgapps.sh << 'EOF'
#!/bin/bash

# NikGapps to Vendor GMS Converter
# Usage: ./convert_nikgapps.sh <nikgapps.zip>

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <nikgapps.zip>"
    echo "Example: $0 NikGapps-stock-arm64-16.zip"
    exit 1
fi

NIKGAPPS_ZIP="$1"

if [ ! -f "$NIKGAPPS_ZIP" ]; then
    echo "Error: $NIKGAPPS_ZIP not found!"
    exit 1
fi

echo "=== NikGapps to Vendor GMS Converter ==="
echo "Input: $NIKGAPPS_ZIP"
echo ""

# Create extraction directory
EXTRACT_DIR="nikgapps_extracted_$$"
mkdir -p "$EXTRACT_DIR"

echo "[1/12] Extracting NikGapps zip..."
unzip -q "$NIKGAPPS_ZIP" -d "$EXTRACT_DIR"

echo "[2/12] Finding AppSet directory..."
cd "$EXTRACT_DIR"

# Find and keep only AppSet, delete everything else
if [ -d "AppSet" ]; then
    echo "[3/12] Cleaning up non-AppSet files..."
    find . -maxdepth 1 ! -name 'AppSet' ! -name '.' -exec rm -rf {} + 2>/dev/null || true
    
    echo "[4/12] Renaming AppSet to gms..."
    mv AppSet gms
    cd gms
else
    echo "Error: AppSet directory not found!"
    exit 1
fi

echo "[5/12] Extracting individual app zips..."
find . -name "*.zip" -exec sh -c 'echo "Extracting $1..."; unzip -q "$1" -d "${1%.zip}"' _ {} \;

echo "[6/12] Removing zip files..."
find . -name "*.zip" -exec rm -v {} \;

echo "[7/12] Removing installer scripts..."
find . \( -name "installer.sh" -o -name "uninstaller.sh" \) -exec rm -v {} \;

echo "[8/12] Renaming directory structure (phase 1)..."
find . -depth -name "___*" -exec bash -c 'old="$1"; new=$(dirname "$old")/$(basename "$old" | sed "s/___/\//g"); newdir=$(dirname "$new"); mkdir -p "$newdir"; mv -v "$old" "$new" 2>/dev/null || true' _ {} \;

echo "[9/12] Renaming directory structure (phase 2 - cleanup)..."
find . -depth -name "___*" -exec bash -c 'mv -v "$1" "$(echo "$1" | sed "s/___//g")" 2>/dev/null || true' _ {} \;

echo "[10/12] Creating vendor structure..."
mkdir -p prebuilt/common/{app,priv-app,etc,framework,lib,lib64,overlay,usr,system}
mkdir -p config/{permissions,sysconfig,default-permissions,security}

echo "[11/12] Moving files to vendor structure..."

# Move APKs
find . -path "*/app/*" -name "*.apk" ! -path "./prebuilt/*" -exec bash -c 'appname=$(basename $(dirname "$1")); mkdir -p prebuilt/common/app/$appname; mv -v "$1" prebuilt/common/app/$appname/' _ {} \;

find . -path "*/priv-app/*" -name "*.apk" ! -path "./prebuilt/*" -exec bash -c 'appname=$(basename $(dirname "$1")); mkdir -p prebuilt/common/priv-app/$appname; mv -v "$1" prebuilt/common/priv-app/$appname/' _ {} \;

# Move overlays
find . -path "*/overlay/*" -name "*.apk" ! -path "./prebuilt/*" -exec mv -v {} prebuilt/common/overlay/ \;

# Move config files
find . -path "*/etc/permissions/*" -type f ! -path "./config/*" -exec mv -v {} config/permissions/ \;
find . -path "*/etc/sysconfig/*" -type f ! -path "./config/*" -exec mv -v {} config/sysconfig/ \;
find . -path "*/etc/default-permissions/*" -type f ! -path "./config/*" -exec mv -v {} config/default-permissions/ \;
find . -path "*/etc/security/*" -type f ! -path "./config/*" -exec bash -c 'mkdir -p config/security/fsverity; cp -rv "$1" config/security/' _ {} \;

# Move framework
find . -name "*.jar" ! -path "./prebuilt/*" -exec mv -v {} prebuilt/common/framework/ \;

# Move libraries
find . -path "*/lib/*" -name "*.so" ! -path "*/arm64/*" ! -path "./prebuilt/*" -exec mv -v {} prebuilt/common/lib/ \;
find . -path "*/lib64/*" -name "*.so" ! -path "./prebuilt/*" -exec mv -v {} prebuilt/common/lib64/ \;
find . -path "*/lib/arm64/*" -name "*.so" ! -path "./prebuilt/*" -exec bash -c 'mkdir -p prebuilt/common/lib/arm64; mv -v "$1" prebuilt/common/lib/arm64/' _ {} \;

# Move usr (GBoard data)
find . -type d -name "usr" -path "*/GBoard/*/usr" ! -path "./prebuilt/*" -exec cp -rv {} prebuilt/common/ \;

# Move system files (textclassifier)
find . -path "*/system/etc/textclassifier/*" -type f ! -path "./prebuilt/*" -exec bash -c 'mkdir -p prebuilt/common/system/etc/textclassifier; cp -v "$1" prebuilt/common/system/etc/textclassifier/' _ {} \;

echo "[12/12] Creating build files..."

# Create vendor.mk
cat > vendor.mk << 'VENDOR_MK'
# GApps vendor makefile

# Include package list
$(call inherit-product, vendor/gms/gapps-packages.mk)

# Copy prebuilt files
PRODUCT_COPY_FILES += \
    $(call find-copy-subdir-files,*,vendor/gms/prebuilt/common/app,$(TARGET_COPY_OUT_PRODUCT)/app) \
    $(call find-copy-subdir-files,*,vendor/gms/prebuilt/common/priv-app,$(TARGET_COPY_OUT_PRODUCT)/priv-app) \
    $(call find-copy-subdir-files,*,vendor/gms/prebuilt/common/overlay,$(TARGET_COPY_OUT_PRODUCT)/overlay) \
    $(call find-copy-subdir-files,*,vendor/gms/prebuilt/common/framework,$(TARGET_COPY_OUT_PRODUCT)/framework) \
    $(call find-copy-subdir-files,*,vendor/gms/prebuilt/common/lib,$(TARGET_COPY_OUT_PRODUCT)/lib) \
    $(call find-copy-subdir-files,*,vendor/gms/prebuilt/common/lib64,$(TARGET_COPY_OUT_PRODUCT)/lib64) \
    $(call find-copy-subdir-files,*,vendor/gms/prebuilt/common/usr,$(TARGET_COPY_OUT_PRODUCT)/usr) \
    $(call find-copy-subdir-files,*,vendor/gms/prebuilt/common/system,$(TARGET_COPY_OUT_SYSTEM)) \
    $(call find-copy-subdir-files,*,vendor/gms/config/permissions,$(TARGET_COPY_OUT_PRODUCT)/etc/permissions) \
    $(call find-copy-subdir-files,*,vendor/gms/config/sysconfig,$(TARGET_COPY_OUT_PRODUCT)/etc/sysconfig) \
    $(call find-copy-subdir-files,*,vendor/gms/config/default-permissions,$(TARGET_COPY_OUT_PRODUCT)/etc/default-permissions) \
    $(call find-copy-subdir-files,*,vendor/gms/config/security,$(TARGET_COPY_OUT_PRODUCT)/etc/security)
VENDOR_MK

# Create gapps-packages.mk
cat > gapps-packages.mk << 'PACKAGES_MK'
# Core GApps packages
PRODUCT_PACKAGES += \
    PrebuiltGmsCoreVic \
    GoogleServicesFramework \
    Phonesky \
    GoogleCalendarSyncAdapter \
    GoogleContactsSyncAdapter

# Optional GApps
PRODUCT_PACKAGES += \
    CarrierServices \
    DeviceHealthServices \
    DigitalWellbeing \
    Drive \
    GBoard \
    GoogleCalculator \
    GoogleCalendar \
    GoogleClock \
    GoogleContacts \
    GoogleDialer \
    DocumentsUIGoogle \
    FilesPrebuilt \
    StorageManagerGoogle \
    GoogleKeep \
    GoogleLocationHistory \
    GoogleMaps \
    GoogleMessages \
    GooglePhotos \
    GoogleRecorder \
    GoogleAssistant \
    GoogleSearch \
    GoogleSounds \
    GoogleTTS \
    MarkupGoogle \
    PlayGames

# Pixel Specifics
PRODUCT_PACKAGES += \
    AICore \
    DevicePersonalizationServices \
    EmojiWallpaper \
    GoogleWallpaper \
    PixelLauncher \
    PixelThemes \
    PixelWeather \
    PrivateComputeServices \
    QuickAccessWallet \
    SettingsServices

# Setup Wizard
PRODUCT_PACKAGES += \
    GoogleOneTimeInitializer \
    GoogleRestore \
    SetupWizard
PACKAGES_MK

# Create Android.mk
cat > Android.mk << 'ANDROID_MK'
LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
ANDROID_MK

# Create BoardConfig.mk
cat > BoardConfig.mk << 'BOARD_MK'
# GApps Board Configuration
BOARD_MK
EOF
