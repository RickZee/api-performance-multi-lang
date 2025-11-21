Output docs/test-runner-all-apis-demo.gif
Set FontSize 14
Set Width 1400
Set Height 900
Set Theme "Catppuccin Mocha"
Set PlaybackSpeed 8.0
Set TypingSpeed 20ms

Type "cd "
Sleep 500ms
Type "$(pwd)"
Enter
Sleep 1s

Type "python load-test/shared/run-tests.py smoke --payload-size 400b --payload-size 4k"
Enter

# Wait for all tests to complete
# Based on actual test runs: 8 APIs × 3 payload sizes = 24 tests
# Each test takes ~8-9 seconds (including overhead)
# Total: 24 tests × 9s = ~216s (3.6 minutes)
# Adding buffer: ~240s (4 minutes)
# At 5x playback speed, this becomes ~48 seconds in the final GIF
Sleep 120s

Sleep 3s
