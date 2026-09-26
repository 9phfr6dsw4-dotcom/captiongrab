on run argv
    if (count of argv) is not 1 then error "Exactly one public video URL is required."
    set publicVideoURL to item 1 of argv

    tell application id "com.captiongrab.app" to activate
    tell application "System Events"
        tell process "CaptionGrab"
            set frontmost to true
            repeat 20 times
                if exists window 1 then exit repeat
                delay 0.25
            end repeat
            if not (exists window 1) then error "CaptionGrab did not open its main window."
            if not (exists text field 1 of window 1) then error "CaptionGrab's YouTube link field is unavailable."
            click text field 1 of window 1
            keystroke publicVideoURL
            key code 36
        end tell
    end tell
end run
