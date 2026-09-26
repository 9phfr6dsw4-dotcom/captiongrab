on run argv
    if (count of argv) is not 1 then error "Exactly one public video ID is required."
    set expectedVideoID to item 1 of argv

    tell application id "com.captiongrab.app" to activate
    tell application "System Events"
        tell process "CaptionGrab"
            set frontmost to true
            repeat 60 times
                if exists window 1 then
                    set accessibleText to {}
                    try
                        repeat with uiElement in (static texts of window 1)
                            try
                                set itemValue to value of uiElement as text
                                if itemValue is not "" then set end of accessibleText to itemValue
                            end try
                        end repeat
                    end try
                    try
                        set linkValue to value of text field 1 of window 1 as text
                        if linkValue is not "" then set end of accessibleText to linkValue
                    end try

                    set previousDelimiters to AppleScript's text item delimiters
                    set AppleScript's text item delimiters to linefeed
                    set accessibleText to accessibleText as text
                    set AppleScript's text item delimiters to previousDelimiters
                    if accessibleText contains "YouTube Video url" and accessibleText contains expectedVideoID then
                        return accessibleText
                    end if
                end if
                delay 5
            end repeat
            error "CaptionGrab did not expose the selected video's transcript through accessibility."
        end tell
    end tell
end run
