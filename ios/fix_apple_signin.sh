#!/bin/bash

echo "Starting to fix Apple Sign In issues..."

# 1. Info.plist 확인
echo "Checking Info.plist..."
INFO_PLIST="Runner/Info.plist"

if [ -f "$INFO_PLIST" ]; then
    # CFBundleURLTypes이 올바르게 설정되어 있는지 확인
    URL_SCHEME_EXISTS=$(plutil -p "$INFO_PLIST" | grep -c "com.pikabook.app")
    
    if [ "$URL_SCHEME_EXISTS" -eq 0 ]; then
        echo "URL scheme not properly set. Please add com.pikabook.app URL scheme in Info.plist"
    else
        echo "URL scheme is set correctly"
    fi
else
    echo "Info.plist not found at $INFO_PLIST"
fi

# 2. entitlements 파일 확인
echo "Checking entitlements file..."
ENTITLEMENTS="Runner/Runner.entitlements"

if [ -f "$ENTITLEMENTS" ]; then
    # com.apple.developer.applesignin이 설정되어 있는지 확인
    APPLESIGNIN_EXISTS=$(plutil -p "$ENTITLEMENTS" | grep -c "com.apple.developer.applesignin")
    
    if [ "$APPLESIGNIN_EXISTS" -eq 0 ]; then
        echo "Apple Sign In entitlement not found. Please add com.apple.developer.applesignin entitlement"
    else
        echo "Apple Sign In entitlement is set correctly"
    fi
else
    echo "Runner.entitlements not found at $ENTITLEMENTS"
    echo "Creating entitlements file..."
    
    cat > "$ENTITLEMENTS" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.applesignin</key>
    <array>
        <string>Default</string>
    </array>
</dict>
</plist>
EOF
    
    echo "Created entitlements file with Apple Sign In capability"
fi

# 3. Podfile 확인
echo "Checking Podfile..."
PODFILE="Podfile"

if [ -f "$PODFILE" ]; then
    # 필요한 설정이 있는지 확인
    PLATFORM_IOS_EXISTS=$(grep -c "platform :ios" "$PODFILE")
    
    if [ "$PLATFORM_IOS_EXISTS" -eq 0 ]; then
        echo "No iOS platform specified in Podfile"
    else
        IOS_VERSION=$(grep "platform :ios" "$PODFILE" | sed -E 's/.*platform :ios, "([0-9.]+)".*/\1/')
        echo "iOS version in Podfile: $IOS_VERSION"
        
        if (( $(echo "$IOS_VERSION < 13.0" | bc -l) )); then
            echo "Warning: iOS version is less than 13.0, which is required for Apple Sign In"
        fi
    fi
fi

echo "Fix script completed. Please check the output above for any issues."

# 4. 프로젝트 설정 안내
echo ""
echo "IMPORTANT: Please make sure the following settings are correctly configured in Xcode:"
echo "1. 'Signing & Capabilities' tab: Make sure 'Sign in with Apple' capability is added"
echo "2. Build Settings: Ensure Code Signing Identity is correctly set"
echo "3. Ensure your Apple Developer account has 'Sign in with Apple' enabled"
echo ""
echo "After fixing these settings, clean and rebuild your project:"
echo "$ flutter clean"
echo "$ cd ios && pod install && cd .."
echo "$ flutter run" 