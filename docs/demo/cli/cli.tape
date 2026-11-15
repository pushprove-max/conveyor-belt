# The demo's beats 10 and 11 as one Claude Code session (run.sh runs this tape with VHS in record-cli.sh's container):
# /units beside the chat while the cards move, then the Foreman: "start your role", the wake naming the blocked
# card, its question with a picker, the pick, the retry and the card back on the belt. Only what is shown is in
# the video: each wait for Claude is hidden, and every part shown is a fixed length, so a re-run gives the same
# beats. The /units part is the first 9 s shown (run.sh B9 cuts there): change both together.
Output "/out/cli.mp4"
Set Shell "bash"
Set FontSize 16
Set Width 1280
Set Height 720
Set Padding 16
Set TypingSpeed 60ms
Set Framerate 30

Hide
Type "export PS1='$ ' && clear"
Enter
# The story clock starts as Claude Code does (mock.js go).
Type "conveyor.sh go && clear && claude"
Enter
Wait+Screen@120s /❯/
Sleep 2s
# Claude Code's own first-run notices are cleared, so the clips show the session and the plugin.
Type "/clear"
Enter
Wait+Screen@60s /❯/
Sleep 2s
Type "/units pane on"
Enter
Wait+Screen@60s /#41/
Sleep 1s

# Beat 10: the cards move along the belt in the /units pane (9 s shown).
Show
Sleep 9s
Hide

# Beat 11: the Foreman.
Show
Type "start your role"
Sleep 400ms
Enter
Hide
# The watchers start at the end of the turn; their wake names #44, and the Foreman asks by the picker.
Wait+Screen@300s /Retry #44/
Show
Sleep 5s
Enter
Hide
Wait+Screen@180s /back on the belt/
Sleep 2s
Show
Sleep 5s
