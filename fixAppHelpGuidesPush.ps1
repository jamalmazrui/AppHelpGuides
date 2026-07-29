# fixAppHelpGuidesPush.ps1
# Clears GitHub's secret-scanning block on the AppHelpGuides repository.
# Writes fixAppHelpGuidesPush.log beside itself. No switches needed.
#
# Why a third version. The first two guessed at what GitHub objects to, by
# scanning for token shapes I chose. That is backwards: GitHub already names
# the file and the line numbers in its rejection message. So this version asks
# it. It attempts the push, reads the refusal, untracks exactly the files
# GitHub named, rebuilds the commits, and tries again -- up to three rounds,
# which is enough for several offending files.
#
# A pattern scan still runs first, so the obvious cases are cleared without a
# round trip, but nothing depends on that scan being complete.
#
# When the remote already holds a good commit and the local commits sit on top
# of it, only those local commits are rebuilt and the push stays ordinary.
# Otherwise the branch is rebuilt whole and replaces what is on the remote.
#
# Nothing is deleted from disk. Files stop being tracked; they stay where they
# are. Pass -bNoPush to stop before the first push attempt.

param(
    [switch] $bNoPush
)

$ErrorActionPreference = "Stop"

$pathRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$pathLog = Join-Path $pathRoot "fixAppHelpGuidesPush.log"

function writeLog {
    param([string] $sMessage)
    $sStamped = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $sMessage
    Write-Host $sStamped
    Add-Content -Path $pathLog -Value $sStamped -Encoding UTF8
}

function runGit {
    <#
    Run git and return its output, treating a non-zero exit as an answer rather
    than a catastrophe. Standard error is folded into the output, so judge by
    the exit code -- never by whether anything was written.
    #>
    param([string[]] $lArguments, [switch] $bQuiet)

    $sPrevious = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $sOutput = (& git @lArguments 2>&1 | Out-String).Trim()
        $iExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $sPrevious
    }
    if ($iExit -ne 0 -and -not $bQuiet) {
        writeLog "git $($lArguments -join ' ') exited with $iExit"
    }
    return [pscustomobject]@{ Output = $sOutput; ExitCode = $iExit; Ok = ($iExit -eq 0) }
}

function requireTool {
    param([string] $sName, [string] $sWhere)
    if (-not (Get-Command $sName -ErrorAction SilentlyContinue)) {
        writeLog "ERROR: $sName was not found. Install it from $sWhere"
        exit 1
    }
    writeLog "Found $sName"
}

function scannedFiles {
    <#
    Tracked files holding something shaped like a credential. This is a
    convenience, not the authority: GitHub's own refusal is the authority, and
    it scans for far more providers than are listed here.
    #>
    $lPatterns = @(
        "gh[pousr]_[A-Za-z0-9]{16,}",
        "github_pat_[A-Za-z0-9_]{20,}",
        "AKIA[0-9A-Z]{16}",
        "xox[abposr]-[A-Za-z0-9-]{10,}",
        "AIza[0-9A-Za-z_\-]{30,}",
        "sk-[A-Za-z0-9]{20,}",
        "-----BEGIN [A-Z ]*PRIVATE KEY-----"
    )
    $sJoined = ($lPatterns -join "|")

    $result = runGit @("ls-files")
    $lTracked = @()
    if ($result.Ok -and $result.Output) {
        $lTracked = $result.Output -split "`r?`n" | Where-Object { $_ }
    }

    $lHits = @()
    foreach ($sFile in $lTracked) {
        $pathFile = Join-Path $pathRoot $sFile
        if (-not (Test-Path $pathFile)) { continue }
        if ((Get-Item -LiteralPath $pathFile).Length -gt 200MB) { continue }
        $iLine = 0
        foreach ($sLine in [System.IO.File]::ReadLines($pathFile)) {
            $iLine++
            if ([regex]::IsMatch($sLine, $sJoined)) {
                $lHits += [pscustomobject]@{ File = $sFile; Line = $iLine }
            }
        }
    }
    return $lHits
}

function namedByGitHub {
    <#
    The files GitHub itself named in a refusal, as "path: NAME:LINE".
    #>
    param([string] $sOutput)
    $lHits = @()
    foreach ($oMatch in [regex]::Matches($sOutput, "path:\s*(\S+?):(\d+)")) {
        $lHits += [pscustomobject]@{
            File = $oMatch.Groups[1].Value
            Line = [int] $oMatch.Groups[2].Value
        }
    }
    return $lHits
}

function untrackFiles {
    param([object[]] $lHits)
    $lFiles = $lHits | ForEach-Object { $_.File } | Sort-Object -Unique
    foreach ($hit in $lHits) {
        writeLog "  $($hit.File) line $($hit.Line)"
    }
    foreach ($sFile in $lFiles) {
        $result = runGit @("rm", "--cached", "--ignore-unmatch", "--", $sFile)
        if ($result.Ok) { writeLog "Untracked (still on disk): $sFile" }
    }
    $pathIgnore = Join-Path $pathRoot ".gitignore"
    $sIgnore = ""
    if (Test-Path $pathIgnore) { $sIgnore = Get-Content -Path $pathIgnore -Raw }
    $lAdd = @()
    foreach ($sFile in $lFiles) {
        $sRule = ($sFile -replace "\\", "/")
        if ($sIgnore -notmatch [regex]::Escape($sRule)) { $lAdd += $sRule }
    }
    if ($lAdd) {
        $lLines = @("", "# Harvested pages holding sample credentials, which GitHub blocks.") + $lAdd
        Add-Content -Path $pathIgnore -Value ($lLines -join "`r`n") -Encoding UTF8
        writeLog "Added $($lAdd.Count) rule(s) to .gitignore"
    }
    return $lFiles.Count
}

Set-Content -Path $pathLog -Value "" -Encoding UTF8
writeLog "fixAppHelpGuidesPush v4 starting in $pathRoot"
writeLog "This version reads GitHub's own refusal, pushes for you, and needs no switches."

requireTool "git" "https://git-scm.com"
Set-Location $pathRoot

if (-not (Test-Path (Join-Path $pathRoot ".git"))) {
    writeLog "ERROR: this is not a Git repository. Run it inside C:\AppHelpGuides."
    exit 1
}

$result = runGit @("rev-parse", "--abbrev-ref", "HEAD") -bQuiet
$sBranch = if ($result.Ok -and $result.Output) { $result.Output } else { "main" }
writeLog "Branch: $sBranch"

$result = runGit @("ls-remote", "--heads", "origin", $sBranch) -bQuiet
$bPublished = $false
foreach ($sLine in ($result.Output -split "`r?`n")) {
    if ($sLine -match "refs/heads/$sBranch\s*$") { $bPublished = $true }
}

$bDescends = $false
if ($bPublished) {
    $result = runGit @("fetch", "origin", $sBranch) -bQuiet
    if (-not $result.Ok) {
        writeLog "ERROR: could not fetch $sBranch from origin. Check your connection"
        writeLog "and sign-in, then run this again."
        exit 1
    }
    $result = runGit @("merge-base", "--is-ancestor", "FETCH_HEAD", "HEAD") -bQuiet
    $bDescends = $result.Ok
    if ($bDescends) {
        writeLog "The published commit is an ancestor of yours, so only the local"
        writeLog "commits need rebuilding and nothing published will be disturbed."
    } else {
        writeLog "The histories have diverged, so the rebuilt branch will replace what"
        writeLog "is on the remote."
    }
} else {
    writeLog "Nothing has been published yet, so the whole branch can be rebuilt."
}

function rebuiltHistory {
    if ($bPublished -and $bDescends) {
        $result = runGit @("reset", "--soft", "FETCH_HEAD")
        if (-not $result.Ok) { writeLog "ERROR: could not rewind to the published commit"; return $false }
        $result = runGit @("add", "--all")
        if (-not $result.Ok) { writeLog "ERROR: staging failed"; return $false }
        $result = runGit @("status", "--porcelain")
        if ($result.Output) {
            $result = runGit @("commit", "-m", "Add help guides")
            if (-not $result.Ok) { writeLog "ERROR: the commit failed"; return $false }
            writeLog "Rebuilt: one clean commit on top of the published one."
        } else {
            writeLog "Nothing left to commit; the local commits held only blocked files."
        }
        return $true
    }
    $result = runGit @("checkout", "--orphan", "cleanBranchForPush") -bQuiet
    if (-not $result.Ok) {
        # A second round: we are already on the clean branch.
        $result = runGit @("add", "--all")
        if (-not $result.Ok) { writeLog "ERROR: staging failed"; return $false }
        $result = runGit @("commit", "--amend", "--no-edit")
        return $result.Ok
    }
    $result = runGit @("add", "--all")
    if (-not $result.Ok) { writeLog "ERROR: staging failed"; return $false }
    $result = runGit @("commit", "-m",
        "AppHelpGuides: screen reader friendly compendia of official product help")
    if (-not $result.Ok) { writeLog "ERROR: the commit failed"; return $false }
    $result = runGit @("branch", "-D", $sBranch) -bQuiet
    $result = runGit @("branch", "-m", $sBranch)
    if (-not $result.Ok) { writeLog "ERROR: could not rename the clean branch"; return $false }
    writeLog "Rebuilt: one commit for the whole branch."
    return $true
}

# A first pass on the obvious cases, so the usual run needs no round trip.
$lHits = scannedFiles
if ($lHits) {
    writeLog "Files holding something credential-shaped:"
    untrackFiles $lHits | Out-Null
} else {
    writeLog "The pattern scan found nothing; GitHub's own answer will decide."
}

if (-not (rebuiltHistory)) { exit 1 }

if ($bNoPush) {
    writeLog "Stopping before the push because -bNoPush was given."
    writeLog "fixAppHelpGuidesPush v4 finished"
    exit 0
}

$iRound = 0
while ($iRound -lt 3) {
    $iRound++
    writeLog "Pushing (round $iRound)"
    if ($bPublished -and $bDescends) {
        $lPush = @("push", "--set-upstream", "origin", $sBranch)
    } else {
        $lPush = @("push", "--force", "--set-upstream", "origin", $sBranch)
    }
    $result = runGit $lPush -bQuiet
    if ($result.Ok) {
        $result = runGit @("remote", "get-url", "origin") -bQuiet
        writeLog "Pushed to $($result.Output)"
        writeLog "fixAppHelpGuidesPush v4 finished"
        exit 0
    }

    $lNamed = namedByGitHub $result.Output
    if (-not $lNamed -and $result.Output -match "(?i)secret|GH013|push protection") {
        # GitHub objected but phrased it differently. Fall back to any tracked
        # file whose name appears in the refusal.
        writeLog "GitHub objected without naming a path in the usual form; looking for"
        writeLog "tracked filenames mentioned in its message."
        $resultFiles = runGit @("ls-files")
        foreach ($sFile in ($resultFiles.Output -split "`r?`n")) {
            if (-not $sFile) { continue }
            $sLeaf = Split-Path -Leaf $sFile
            if ($result.Output -match [regex]::Escape($sLeaf)) {
                $lNamed += [pscustomobject]@{ File = $sFile; Line = 0 }
            }
        }
    }
    if (-not $lNamed) {
        writeLog "The push failed for a reason other than secret scanning:"
        foreach ($sLine in ($result.Output -split "`r?`n")) {
            if ($sLine.Trim()) { writeLog "  $($sLine.Trim())" }
        }
        exit 1
    }

    writeLog "GitHub refused the push and named these files:"
    $iCount = untrackFiles $lNamed
    if ($iCount -eq 0) {
        writeLog "None of the named files are tracked, so nothing further can be done"
        writeLog "here. Send this log to Claude."
        exit 1
    }
    if (-not (rebuiltHistory)) { exit 1 }
}

writeLog "Three rounds were not enough. Send this log to Claude."
exit 1
