#!/bin/bash
# Toggle input source US <-> Simplified Chinese (ITABC), used by Karabiner Ctrl+Space rule
cur=$(/opt/homebrew/bin/macism)
if [ "$cur" = "com.apple.keylayout.US" ]; then
  /opt/homebrew/bin/macism com.apple.inputmethod.SCIM.ITABC
else
  /opt/homebrew/bin/macism com.apple.keylayout.US
fi
