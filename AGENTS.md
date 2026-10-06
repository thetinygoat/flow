# guidelines

1. if a code comment explains how instead of why its unncessary, your code is too complicated, delete the comment and make the code better
2. Do not refer to local files and folders in you code comments for example, the comment below is a bad comment because it refers to ../ghostty
   > # Builds libghostty from ../ghostty (branch flow-build: v1.3.1 + two Xcode 27)
3. the vendor/ghostty directory will show as changed to git due to patches, ignore it.
4. the repo rules on github dont allow to publish direfctly to main branch, every new feature you work on create a new branch and open a pr once done. Never opne a pr without approval first.
5. if you have fixed something in the terminal, close the old debug build if running, and start a new one.
