# Windows Voice Access for Wispr Flow

Say **“begin dictation”** to start a hands-free Wispr Flow recording. Say **“end dictation”** to stop recording, paste the transcript and restore the Voice Access mode you started in. If you began in default mode, ordinary speech can enter text again. If you began in command mode, Voice Access keeps listening for commands.

## Set up on another PC

1. On x64 Windows 11, open **Settings → Accessibility → Speech → Voice access**. Finish microphone and language setup, select **English (United States)** and confirm that **“open voice shortcuts”** opens the shortcuts page. This release configures the `en-US` profile. The spoken workflow was tested on Windows 11 25H2, build 26200. [Microsoft’s voice shortcut guide](https://support.microsoft.com/en-us/accessibility/windows/voice-access/use-voice-to-create-voice-access-shortcuts)
2. Install Wispr Flow, sign in and allow microphone access. In Flow’s keyboard shortcut settings, set **hands-free** to **Ctrl + Windows + Space**. In a scratch text field, check that one press starts recording and a second press stops it and pastes text. [Wispr Flow hands-free setup](https://docs.wisprflow.ai/articles/6391241694-use-flow-hands-free)
3. In a normal PowerShell window, run the commands below. The installer builds the helper with the Windows .NET Framework compiler, checks its SHA-256, starts it and registers it at sign-in for your account.

```powershell
git clone --branch v0.1.0 https://github.com/brycelelbach/windows-voice-access-wispr-flow.git
cd windows-voice-access-wispr-flow
.\install.ps1
```

   For installation without Git, extract the **Windows.Voice.Access.Wispr.Flow.zip** release asset, open PowerShell in the extracted folder and run `.\install.ps1`. This path verifies the bundled executable. If local script execution is restricted, inspect the scripts and run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1` for that process. [Download v0.1.0](https://github.com/brycelelbach/windows-voice-access-wispr-flow/releases/tag/v0.1.0)

4. When the installer reports `ConfigChanged = True`, restart Voice Access to load the two phrases. Use the Voice Access Settings menu to turn it off, then launch **Voice access** from Start or Accessibility settings. If the toolbar says **Sleep mode**, say **“Voice access wake up.”**
5. In a scratch text field, say **“switch to default mode,”** then **“begin dictation.”** Wait for Flow’s recording cue, dictate a sentence and say **“end dictation.”** Check that the sentence appears and the Command mode label clears. Repeat after saying **“switch to command mode.”** This time the Command mode label should remain. Windows can briefly display **“Cannot open …Return to default.lnk”** on this branch. Your next voice command works immediately.

## Optional stop-phrase cleanup

Flow can hear the words used to stop it before the recording ends. The original setup used four personal snippets with empty expansions, namely `end dictation`, `end dictation.`, `and dictation` and `and dictation.`. The last two cover a common mishearing. Flow removes matching phrases anywhere in a transcript, including intentional mentions. Adjacent punctuation or whitespace can remain. [Wispr Flow snippet behavior](https://docs.wisprflow.ai/articles/5784437944-create-and-use-snippets)

To reproduce those rules on a Windows desktop version whose snippet editor rejects empty expansions, quit Flow, run the following from the source checkout or extracted ZIP with Python 3, then reopen Flow. The script uses one SQLite transaction, preserves unrelated entries and stops on a conflicting active personal rule. You can remove these entries later under **Flow → Snippets → Personal**.

```powershell
py -3 scripts/stop-phrase-snippets.py
```

## How the two shortcuts work

| Phrase | Actions in order |
| --- | --- |
| **begin dictation** | Signal the helper with Ctrl + Alt + Shift + F9 to remember the starting mode. Switch Voice Access to command mode. Send Flow’s Ctrl + Windows + Space toggle. |
| **end dictation** | Send the Flow toggle. Select command mode as the fallback. Signal the helper with Ctrl + Alt + Shift + F10. Open the temporary shortcut. If it opens successfully, execute the native default-mode action. |

The helper reads a narrow strip at the right edge of the Voice Access toolbar when it receives the first signal. It recognizes default mode from a blank mode label next to visible toolbar controls. The second signal creates a five-second `Return to default.lnk` only when the stored default reading belongs to the same Voice Access window and process. A missing link ends the native action sequence and leaves command mode active. A covered toolbar, an unreadable indicator or a restarted Voice Access process also selects this fallback.

The helper keeps the reading in memory. It registers two global hotkeys and takes a toolbar sample on demand. Flow handles microphone capture and transcription. The spoken phrases require Voice Access to be awake in default or command mode. After manually stopping or canceling Flow, check the recording indicator before saying either phrase, since both send the same toggle.

## Installation and removal

The installer merges two shortcuts into `%APPDATA%\VoiceAccess\CustomCommands\en-US\CustomCommands.json`. It creates this file on a fresh profile and preserves unrelated commands. It writes a timestamped backup alongside each existing file it changes and prints the backup path. A conflicting phrase or intent stops installation so you can resolve it in Voice Access. A matching installation can be rerun without duplicating commands or replacing their IDs.

The executable, license and default-mode shortcut template live in `%APPDATA%\VoiceAccess\WisprModeMemory`. **Wispr Voice Access Mode Memory.lnk** in the current user’s Startup folder launches the listener at sign-in. If the helper exits immediately, check for another copy or an app using Ctrl + Alt + Shift + F9 or F10. If a Windows update changes toolbar geometry or the native shortcut format, repeat the two spoken checks above.

To remove the helper, login item and matching voice shortcuts, run the following from the checkout or extracted ZIP, then restart Voice Access. Flow snippets are managed separately in Flow.

```powershell
.\install.ps1 -Uninstall
```

## Reproduce the executable and test setup

```powershell
$app = .\build.ps1
Get-FileHash -Algorithm SHA256 -LiteralPath $app.FullName
.\tests\install-test.ps1
py -3 tests/snippets-test.py
```

To check the installed version, open the properties of `VoiceModeMemory.exe` and look under **Details → Product version**. For this release it reads `0.1.0`. The release build uses the Windows Framework64 C# compiler (release compiler version `4.8.9221.0`), restores the recorded PE timestamp and module ID, then checks the SHA-256. Use `.\build.ps1 -Development` for a modified source tree. [Release hash and build metadata](release.json)

The installer tests use a temporary profile. On a Windows test machine with the two hotkeys available, `.\tests\install-test.ps1 -ExerciseProcess` also starts the listener and verifies that reinstall keeps a single instance. GitHub Actions runs this check on Windows. Use the spoken checks under setup to verify the microphone, Flow and toolbar on the target PC.

## License

Apache License 2.0 with LLVM Exceptions. SPDX identifier `Apache-2.0 WITH LLVM-exception`. [Full license](LICENSE)
