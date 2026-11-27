# PenBar offline dictation helper.
# Listens with Windows' built-in speech recognizer while the flag file exists
# and types what you say into the app you're using. No window, no overlay.
# Started by PenBar; exits on its own when PenBar closes.
param([string]$Flag, [int]$PenBarPid = 0)

Add-Type -AssemblyName System.Speech
Add-Type -AssemblyName System.Windows.Forms

$engine = New-Object System.Speech.Recognition.SpeechRecognitionEngine
$engine.LoadGrammar((New-Object System.Speech.Recognition.DictationGrammar))
$engine.SetInputToDefaultAudioDevice()

while ($true) {
    if ($PenBarPid -and -not (Get-Process -Id $PenBarPid -ErrorAction SilentlyContinue)) { break }
    if (Test-Path -LiteralPath $Flag) {
        $result = $engine.Recognize([TimeSpan]::FromSeconds(1))
        if ($result -and $result.Confidence -gt 0.25 -and (Test-Path -LiteralPath $Flag)) {
            # SendKeys treats + ^ % ~ ( ) { } [ ] specially: wrap them in braces
            $text = [regex]::Replace($result.Text + ' ', '[+^%~(){}\[\]]', '{$0}')
            [System.Windows.Forms.SendKeys]::SendWait($text)
        }
    } else {
        Start-Sleep -Milliseconds 100
    }
}
$engine.Dispose()
