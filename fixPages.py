"""fixPages.py version 3

Rebuilds the .htm beside every .md in a folder, each with exactly ONE level-one heading.

THE FAULT IT REPAIRS. A guide often gives its title twice, once in the front matter as `title:` and once as the
`# ` heading at the top of the text, and Pandoc made both into level-one headings; a screen reader user moving by
heading met the title twice. A page that uses `# ` for its sections had many level-one headings instead.

THE REPAIR, AND WHERE IT LIVES. Version 2 emptied every page's title, which left a page whose only title was in
its front matter (ReadMe, Announce) with no level-one heading at all. Version 3 lets Pandoc build the page, then
applies the kit's one rule, oneTitleHeading in HomerDev's scripts\\fixEncoding.py, which every Homer build uses:
a repeated title keeps one copy, an author's single `# ` heading stays the page's heading, section headings below
the title move down a level, and a page with none gets its own title as its heading. Without the kit, it falls back
to version 2's way. The newest Pandoc on the computer is used, as the kit's tools choose it, and every page is
written in the Homer encoding (UTF-8 with a BOM, CRLF).

RUN IT WITH NO ARGUMENTS to rebuild every page in the folder it sits in, or give it a folder. It names each guide
before working on it, with its number and the total; the biggest guides take Pandoc several seconds each.
"""

import importlib.util, io, logging, os, platform, re, shutil, subprocess, sys

c_sLogName = "fixPages.log"


def startLog():
    sHere = os.path.dirname(os.path.abspath(__file__))
    sPath = os.path.join(sHere, c_sLogName)
    logging.basicConfig(filename=sPath, filemode="w", level=logging.INFO,
                        format="%(asctime)s %(levelname)s %(message)s", encoding="utf-8", errors="backslashreplace")
    logging.info("fixPages.py version 3 running under Python %s on %s", platform.python_version(), platform.platform())
    logging.info("script at %s, working directory %s", os.path.abspath(__file__), os.getcwd())
    logging.info("command line: %s", " ".join(sys.argv))
    return sPath


def readText(sPath):
    binBody = io.open(sPath, "rb").read()
    for sEncoding in ("utf-8-sig", "utf-8", "cp1252", "latin-1"):
        try: return binBody.decode(sEncoding)
        except UnicodeDecodeError: continue
    return binBody.decode("utf-8", "replace")


def titleOf(sMarkdown):
    """The guide's own title: its front matter line, or its first heading."""
    oFront = re.search(r'(?m)^title:\s*"?([^"\n]+)"?\s*$', sMarkdown[:800])
    if oFront: return oFront.group(1).strip()
    oHeading = re.search(r"(?m)^# (.+)$", sMarkdown)
    return oHeading.group(1).strip() if oHeading else "Help guide"


def findPandoc():
    """The newest Pandoc on this computer: each copy found is asked its version."""
    lCandidates = []
    sOnPath = shutil.which("pandoc")
    if sOnPath: lCandidates.append(sOnPath)
    for sBase in (os.environ.get("ProgramFiles", ""), os.environ.get("LOCALAPPDATA", "")):
        sPath = os.path.join(sBase, "Pandoc", "pandoc.exe") if sBase else ""
        if sPath and os.path.isfile(sPath) and sPath.lower() not in [s.lower() for s in lCandidates]: lCandidates.append(sPath)
    tBest, sBest = (), ""
    for sPath in lCandidates:
        try:
            sFirst = subprocess.run([sPath, "--version"], capture_output=True, text=True, timeout=30).stdout.splitlines()[0]
            tVersion = tuple(int(s) for s in re.findall(r"\d+", sFirst.split()[-1]))
        except Exception:
            continue
        logging.info("pandoc candidate %s, version %s", sPath, ".".join(str(i) for i in tVersion))
        if tVersion > tBest: tBest, sBest = tVersion, sPath
    return sBest


def kitHeadingRule():
    """oneTitleHeading from the kit's scripts\\fixEncoding.py: the HomerDev variable's kit, then C:\\HomerDev."""
    for sKit in (os.environ.get("HomerDev", ""), r"C:\HomerDev"):
        sPath = os.path.join(sKit, "scripts", "fixEncoding.py") if sKit else ""
        if sPath and os.path.isfile(sPath):
            try:
                oSpec = importlib.util.spec_from_file_location("homerFixEncoding", sPath)
                oModule = importlib.util.module_from_spec(oSpec); oSpec.loader.exec_module(oModule)
                logging.info("heading rule: the kit's, %s", sPath)
                return oModule.oneTitleHeading
            except Exception as oError:
                logging.warning("the kit's fixEncoding.py could not be loaded: %s", oError)
    logging.warning("the kit was not found, so pages are built the version 2 way, with the title emptied")
    return None


def buildPage(sPandoc, fnRule, sMarkdownPath, sTitle):
    sPagePath = sMarkdownPath[:-3] + ".htm"
    lCommand = [sPandoc, sMarkdownPath, "-f", "markdown", "-t", "html5", "--standalone",
                "--toc", "--toc-depth=2", "-M", "pagetitle=" + sTitle, "-o", sPagePath]
    if not fnRule: lCommand[-2:-2] = ["-M", "title="]
    logging.info("running: %s", " ".join(lCommand))
    oResult = subprocess.run(lCommand, capture_output=True)
    if oResult.returncode != 0:
        logging.error("Pandoc exited with %d for %s: %s", oResult.returncode, sMarkdownPath,
                      oResult.stderr.decode("utf-8", "replace")[:400])
        return False
    sPage = readText(sPagePath).replace("\r\n", "\n")
    if fnRule: sPage = fnRule(sPage)
    io.open(sPagePath, "wb").write(b"\xef\xbb\xbf" + sPage.replace("\n", "\r\n").encode("utf-8"))
    iHeadings = len(re.findall(r"(?i)<h1\b", sPage))
    logging.info("%s: %d bytes, %d level-one heading(s)", sPagePath, len(sPage), iHeadings)
    if iHeadings != 1:
        logging.warning("%s has %d level-one headings", sPagePath, iHeadings)
    return iHeadings == 1


def main():
    sLogPath = startLog()
    sFolder = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    sPandoc = findPandoc()
    if not sPandoc:
        print("Pandoc was not found. Install Pandoc and run this again.")
        logging.error("Pandoc was not found")
        return 1
    logging.info("pandoc chosen: %s", sPandoc)
    fnRule = kitHeadingRule()
    lNames = sorted(s for s in os.listdir(sFolder) if s.lower().endswith(".md"))
    iBuilt, iOdd = 0, 0
    print("Rebuilding %d page%s in %s" % (len(lNames), "" if len(lNames) == 1 else "s", sFolder))
    print("A large guide takes Pandoc several seconds; the name appears before the work.")
    for iIndex, sName in enumerate(lNames, 1):
        sPath = os.path.join(sFolder, sName)
        sTitle = titleOf(readText(sPath))
        sys.stdout.write("%d of %d: %s\n" % (iIndex, len(lNames), sName))
        sys.stdout.flush()
        if buildPage(sPandoc, fnRule, sPath, sTitle): iBuilt += 1
        else: iOdd += 1
    print("Guides read: %d" % len(lNames))
    print("Pages rebuilt with one level-one heading: %d" % iBuilt)
    if iOdd: print("Pages needing a look: %d (named in the log)" % iOdd)
    print("Log: " + sLogPath)
    return 1 if iOdd else 0


if __name__ == "__main__":
    sys.exit(main())
