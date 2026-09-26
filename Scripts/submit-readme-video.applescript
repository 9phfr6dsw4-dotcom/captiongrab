on run
    tell application "System Events"
        tell process "CaptionGrab"
            set frontmost to true
            key code 36
        end tell
    end tell
end run
