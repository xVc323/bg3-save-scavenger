#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

usage() {
  cat <<'EOF'
Usage: fix_profile8.sh [--profile PATH] [--tool PATH] [--workdir PATH] [--no-auto-install] [--force] [--verbose] [--color {auto|always|never}]

Defaults:
  --profile  auto-detect under ~/Documents/Larian Studios/Baldur's Gate 3/PlayerProfiles
  --tool     divine|Divine|ConverterApp found in PATH (or provide full path)

Notes:
  - The conversion tool must support:
      -a convert-resource -g bg3 -s INPUT -d OUTPUT
  - Provide a .dll path to run via dotnet automatically.
  - If no tool is found, the script will auto-install:
      - macOS: build LSLib from source (requires git + dotnet)
      - other: download latest LSLib release
  - Default is quiet; use --verbose to see build logs.
  - Default continues even if the block is absent; use --force to be explicit.
  - Backups are stored next to the file and under: ~/Documents/bg3_backups (override with BACKUP_DIR).
  - Color is enabled by default; disable with --color never or NO_COLOR=1.

Example (local run):
  ./fix_profile8.sh --tool "/path/to/Divine" --profile "/path/to/profile8.lsf"

Example (curl one-shot):
  curl -fsSL https://your-host/fix_profile8.sh | bash -s -- \
    --tool "/path/to/Divine" \
    --profile "/Users/$USER/Documents/Larian Studios/Baldur's Gate 3/PlayerProfiles/Public/profile8.lsf"
EOF
}

DEFAULT_PROFILE="$HOME/Documents/Larian Studios/Baldur's Gate 3/PlayerProfiles/Public/profile8.lsf"
PROFILE_PATH="$DEFAULT_PROFILE"
BACKUP_DIR="${BACKUP_DIR:-$HOME/Documents/bg3_backups}"
TOOL_PATH=""
WORK_DIR=""
PYTHON_BIN="${PYTHON_BIN:-python3}"
AUTO_INSTALL=1
FORCE=1
VERBOSE=0
COLOR_MODE="auto"
LOG_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE_PATH="$2"
      shift 2
      ;;
    --tool)
      TOOL_PATH="$2"
      shift 2
      ;;
    --workdir)
      WORK_DIR="$2"
      shift 2
      ;;
    --no-auto-install)
      AUTO_INSTALL=0
      shift 1
      ;;
    --force)
      FORCE=1
      shift 1
      ;;
    --verbose)
      VERBOSE=1
      shift 1
      ;;
    --color)
      COLOR_MODE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$TOOL_PATH" ]]; then
  if command -v divine >/dev/null 2>&1; then
    TOOL_PATH="$(command -v divine)"
  elif command -v Divine >/dev/null 2>&1; then
    TOOL_PATH="$(command -v Divine)"
  elif command -v ConverterApp >/dev/null 2>&1; then
    TOOL_PATH="$(command -v ConverterApp)"
  fi
fi

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "Python not found (expected $PYTHON_BIN). Set PYTHON_BIN or install python3." >&2
  exit 1
fi

if [[ -z "$WORK_DIR" ]]; then
  WORK_DIR="$(mktemp -d)"
else
  mkdir -p "$WORK_DIR"
fi
LOG_FILE="$WORK_DIR/build.log"

cleanup() {
  if [[ -z "${KEEP_WORKDIR:-}" ]]; then
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

init_colors() {
  local enable=0
  if [[ "$COLOR_MODE" == "always" ]]; then
    enable=1
  elif [[ "$COLOR_MODE" == "never" ]]; then
    enable=0
  else
    if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
      enable=1
    fi
  fi

  if [[ "$enable" -eq 1 ]]; then
    C_RESET=$'\033[0m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_RED=$'\033[31m'
    C_BLUE=$'\033[34m'
    C_PURPLE=$'\033[35m'
    C_BOLD_ITALIC=$'\033[1;3m'
    C_DIM=$'\033[2m'
  else
    C_RESET=""
    C_GREEN=""
    C_YELLOW=""
    C_RED=""
    C_BLUE=""
    C_PURPLE=""
    C_BOLD_ITALIC=""
    C_DIM=""
  fi
}

log_info() { echo "${C_BLUE}>>${C_RESET} $*"; }
log_ok() { echo "${C_GREEN}OK${C_RESET} $*"; }
log_warn() { echo "${C_YELLOW}WARN${C_RESET} $*"; }
log_error() { echo "${C_RED}ERROR${C_RESET} $*" >&2; }

init_colors

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log_error "Missing dependency: $1"
    exit 1
  fi
}

run_cmd() {
  if [[ "$VERBOSE" -eq 1 ]]; then
    "$@"
  else
    "$@" >>"$LOG_FILE" 2>&1
  fi
}

fail_with_log() {
  if [[ "$VERBOSE" -eq 1 ]]; then
    exit 1
  fi

  log_error "Auto-build failed. See log: $LOG_FILE"
  exit 1
}

build_from_source() {
  require_cmd git
  require_cmd dotnet

  local repo_dir="$WORK_DIR/lslib-src"
  if [[ ! -d "$repo_dir/.git" ]]; then
    run_cmd git clone --depth 1 https://github.com/Norbyte/lslib "$repo_dir" || fail_with_log
  fi

  run_cmd "$PYTHON_BIN" - "$repo_dir/LSLib/LSLib.csproj" <<'PY'
import re
import sys

path = sys.argv[1]
text = open(path, "r", encoding="utf-8").read()

text = text.replace("<PlatformTarget>x64</PlatformTarget>", "<PlatformTarget>AnyCPU</PlatformTarget>")
text = re.sub(
    r"\s*<ItemGroup>\s*<ProjectReference[^>]*LSLibNative\.vcxproj[^>]*/>\s*</ItemGroup>\s*",
    "\n",
    text,
    flags=re.S
)
while "<PreBuildEvent>" in text:
    start = text.index("<PreBuildEvent>")
    end = text.index("</PreBuildEvent>", start) + len("</PreBuildEvent>")
    text = text[:start] + text[end:]

removals = """
  <ItemGroup>
    <Compile Remove=\"LS\\Story\\**\\*.cs\" />
    <Compile Remove=\"LS\\Stats\\*.cs\" />
    <Compile Remove=\"LS\\Mods\\**\\*.cs\" />
    <Compile Remove=\"LS\\Save\\**\\*.cs\" />
    <Compile Remove=\"LS\\ParserCommon.cs\" />
    <Compile Remove=\"LS\\VFS.cs\" />
    <Compile Remove=\"LS\\PackageCommon.cs\" />
    <Compile Remove=\"LS\\PackageReader.cs\" />
    <Compile Remove=\"LS\\PackageWriter.cs\" />
    <Compile Remove=\"Granny\\**\\*.cs\" />
    <Compile Remove=\"VirtualTextures\\**\\*.cs\" />
  </ItemGroup>
"""

if "Compile Remove=\"LS\\Story" not in text:
    text = text.replace("</Project>", f"{removals}\n</Project>")

open(path, "w", encoding="utf-8").write(text)
PY

  run_cmd "$PYTHON_BIN" - "$repo_dir/Divine/Divine.csproj" <<'PY'
import sys

path = sys.argv[1]
text = open(path, "r", encoding="utf-8").read()
text = text.replace("<PlatformTarget>x64</PlatformTarget>", "<PlatformTarget>AnyCPU</PlatformTarget>")
open(path, "w", encoding="utf-8").write(text)
PY

  cat > "$repo_dir/Divine/CLI/CommandLineArguments.cs" <<'EOF'
using CommandLineParser.Arguments;
using LSLib.LS.Enums;

namespace Divine.CLI;

public class CommandLineArguments
{
    [EnumeratedValueArgument(typeof(string), 'l', "loglevel",
        Description = "Set verbosity level of log output",
        DefaultValue = "info",
        AllowedValues = "off;fatal;error;warn;info;debug;trace;all",
        ValueOptional = false,
        Optional = true
    )]
    public string LogLevel;

    [EnumeratedValueArgument(typeof(string), 'g', "game",
        Description = "Set target game when generating output",
        DefaultValue = null,
        AllowedValues = "dos;dosee;dos2;dos2de;bg3",
        ValueOptional = false,
        Optional = false
    )]
    public string Game;

    [ValueArgument(typeof(string), 's', "source",
        Description = "Set source file path",
        DefaultValue = null,
        ValueOptional = false,
        Optional = false
    )]
    public string Source;

    [ValueArgument(typeof(string), 'd', "destination",
        Description = "Set destination file path",
        DefaultValue = null,
        ValueOptional = false,
        Optional = false
    )]
    public string Destination;

    [EnumeratedValueArgument(typeof(string), 'a', "action",
        Description = "Set action to execute",
        DefaultValue = "convert-resource",
        AllowedValues = "convert-resource",
        ValueOptional = false,
        Optional = false
    )]
    public string Action;

    [SwitchArgument("legacy-guids", false,
        Description = "Use legacy GUID serialization format when serializing LSX/LSJ files",
        Optional = true
    )]
    public bool LegacyGuids;

    public static LSLib.LS.Enums.LogLevel GetLogLevelByString(string logLevel)
    {
        return logLevel switch
        {
            "off" => LSLib.LS.Enums.LogLevel.OFF,
            "fatal" => LSLib.LS.Enums.LogLevel.FATAL,
            "error" => LSLib.LS.Enums.LogLevel.ERROR,
            "warn" => LSLib.LS.Enums.LogLevel.WARN,
            "info" => LSLib.LS.Enums.LogLevel.INFO,
            "debug" => LSLib.LS.Enums.LogLevel.DEBUG,
            "trace" => LSLib.LS.Enums.LogLevel.TRACE,
            "all" => LSLib.LS.Enums.LogLevel.ALL,
            _ => LSLib.LS.Enums.LogLevel.INFO
        };
    }

    public static LSLib.LS.Enums.Game GetGameByString(string game)
    {
        return game switch
        {
            "bg3" => LSLib.LS.Enums.Game.BaldursGate3,
            "dos" => LSLib.LS.Enums.Game.DivinityOriginalSin,
            "dosee" => LSLib.LS.Enums.Game.DivinityOriginalSinEE,
            "dos2" => LSLib.LS.Enums.Game.DivinityOriginalSin2,
            "dos2de" => LSLib.LS.Enums.Game.DivinityOriginalSin2DE,
            _ => LSLib.LS.Enums.Game.BaldursGate3
        };
    }
}
EOF

  cat > "$repo_dir/Divine/CLI/CommandLineActions.cs" <<'EOF'
using System;
using System.IO;
using LSLib.LS.Enums;

namespace Divine.CLI;

internal class CommandLineActions
{
    public static string SourcePath;
    public static string DestinationPath;
    public static Game Game;
    public static LogLevel LogLevel;
    public static bool LegacyGuids;

    public static void Run(CommandLineArguments args)
    {
        SetUpAndValidate(args);
        Process(args);
    }

    private static void SetUpAndValidate(CommandLineArguments args)
    {
        LogLevel = CommandLineArguments.GetLogLevelByString(args.LogLevel);
        Game = CommandLineArguments.GetGameByString(args.Game);
        LegacyGuids = args.LegacyGuids;

        SourcePath = TryToValidatePath(args.Source);
        DestinationPath = TryToValidatePath(args.Destination);
    }

    private static void Process(CommandLineArguments args)
    {
        switch (args.Action)
        {
            case "convert-resource":
                CommandLineDataProcessor.Convert();
                break;
            default:
                CommandLineLogger.LogFatal($"Unsupported action: {args.Action}", 1);
                break;
        }
    }

    private static string TryToValidatePath(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            CommandLineLogger.LogFatal("Path cannot be empty", 1);
        }

        return Path.GetFullPath(path);
    }
}
EOF

  cat > "$repo_dir/Divine/CLI/CommandLineDataProcessor.cs" <<'EOF'
using LSLib.LS;
using LSLib.LS.Enums;
using System;
using System.IO;

namespace Divine.CLI;

internal class CommandLineDataProcessor
{
    public static void Convert()
    {
        var conversionParams = ResourceConversionParameters.FromGameVersion(CommandLineActions.Game);
        var loadParams = ResourceLoadParameters.FromGameVersion(CommandLineActions.Game);
        loadParams.ByteSwapGuids = !CommandLineActions.LegacyGuids;
        ConvertResource(CommandLineActions.SourcePath, CommandLineActions.DestinationPath, loadParams, conversionParams);
    }

    private static void ConvertResource(string sourcePath, string destinationPath,
        ResourceLoadParameters loadParams, ResourceConversionParameters conversionParams)
    {
        try
        {
            ResourceFormat resourceFormat = ResourceUtils.ExtensionToResourceFormat(destinationPath);
            CommandLineLogger.LogDebug($"Using destination extension: {resourceFormat}");

            Resource resource = ResourceUtils.LoadResource(sourcePath, loadParams);

            ResourceUtils.SaveResource(resource, destinationPath, resourceFormat, conversionParams);

            CommandLineLogger.LogInfo($"Wrote resource to: {destinationPath}");
        }
        catch (Exception e)
        {
            CommandLineLogger.LogFatal($"Failed to convert resource: {e.Message}", 2);
            CommandLineLogger.LogTrace($"{e.StackTrace}");
        }
    }

    public static void ConvertLoca()
    {
        ConvertLoca(CommandLineActions.SourcePath, CommandLineActions.DestinationPath);
    }

    private static void ConvertLoca(string sourcePath, string destinationPath)
    {
        try
        {
            var loca = LocaUtils.Load(sourcePath);
            LocaUtils.Save(loca, destinationPath);
            CommandLineLogger.LogInfo($"Wrote localization to: {destinationPath}");
        }
        catch (Exception e)
        {
            CommandLineLogger.LogFatal($"Failed to convert localization file: {e.Message}", 2);
            CommandLineLogger.LogTrace($"{e.StackTrace}");
        }
    }
}
EOF

  rm -f \
    "$repo_dir/Divine/CLI/CommandLinePackageProcessor.cs" \
    "$repo_dir/Divine/CLI/CommandLineGR2Processor.cs"

  run_cmd dotnet build "$repo_dir/Divine/Divine.csproj" -c Release || fail_with_log
  TOOL_PATH="$repo_dir/Divine/bin/Release/net8.0/Divine.dll"
  log_ok "Built tool: $TOOL_PATH"
}

auto_install_tool() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    build_from_source
    return
  fi

  local api_url="https://api.github.com/repos/Norbyte/lslib/releases/latest"
  local zip_path="$WORK_DIR/lslib.zip"
  local extract_dir="$WORK_DIR/lslib"

  if ! command -v unzip >/dev/null 2>&1; then
    echo "unzip not found. Install unzip or set --tool to an existing Divine." >&2
    exit 1
  fi

  log_info "Downloading latest LSLib release..."
  local asset_url
  asset_url="$("$PYTHON_BIN" - "$api_url" <<'PY'
import json
import sys
import urllib.request

api_url = sys.argv[1]
with urllib.request.urlopen(api_url) as resp:
    data = json.loads(resp.read().decode("utf-8"))

assets = data.get("assets", [])
def score(name: str) -> int:
    n = name.lower()
    if "exporttool" in n:
        return 0
    if "divine" in n:
        return 1
    if n.endswith(".zip"):
        return 2
    return 9

candidates = [(score(a.get("name","")), a) for a in assets if a.get("browser_download_url")]
candidates.sort(key=lambda x: x[0])
url = candidates[0][1]["browser_download_url"] if candidates else ""
print(url)
PY
)"

  if [[ -z "$asset_url" ]]; then
    log_error "Could not find a downloadable LSLib asset in the latest release."
    exit 1
  fi

  "$PYTHON_BIN" - "$asset_url" "$zip_path" <<'PY'
import sys
import urllib.request

url = sys.argv[1]
out_path = sys.argv[2]
with urllib.request.urlopen(url) as resp, open(out_path, "wb") as f:
    f.write(resp.read())
PY

  mkdir -p "$extract_dir"
  if [[ "$VERBOSE" -eq 1 ]]; then
    unzip -oq "$zip_path" -d "$extract_dir"
  else
    unzip -oq "$zip_path" -d "$extract_dir" >>"$LOG_FILE" 2>&1 || fail_with_log
  fi

  local tool_found
  tool_found="$("$PYTHON_BIN" - "$extract_dir" <<'PY'
import os
import sys

root = sys.argv[1]
targets = ["divine.dll", "converterapp.dll", "divine.exe", "converterapp.exe"]
best = ""
best_idx = len(targets)
for dirpath, _, filenames in os.walk(root):
    for name in filenames:
        lower = name.lower()
        if lower in targets:
            idx = targets.index(lower)
            if idx < best_idx:
                best_idx = idx
                best = os.path.join(dirpath, name)
print(best)
PY
)"

  if [[ -z "$tool_found" ]]; then
    log_error "LSLib downloaded, but no Divine/ConverterApp tool was found."
    exit 1
  fi

  TOOL_PATH="$tool_found"
  log_ok "Using tool: $TOOL_PATH"
}

if [[ -z "$TOOL_PATH" ]]; then
  if command -v divine >/dev/null 2>&1; then
    TOOL_PATH="$(command -v divine)"
  elif command -v Divine >/dev/null 2>&1; then
    TOOL_PATH="$(command -v Divine)"
  elif command -v ConverterApp >/dev/null 2>&1; then
    TOOL_PATH="$(command -v ConverterApp)"
  fi
fi

if [[ -z "$TOOL_PATH" && "$AUTO_INSTALL" -eq 1 ]]; then
  auto_install_tool
fi

if [[ -z "$TOOL_PATH" ]]; then
  log_error "Could not find Divine/ConverterApp in PATH. Use --tool /path/to/Divine."
  exit 1
fi

if [[ ! -f "$PROFILE_PATH" ]]; then
  PROFILE_PATH="$("$PYTHON_BIN" - "$HOME/Documents/Larian Studios/Baldur's Gate 3/PlayerProfiles" <<'PY'
import os
import sys

root = sys.argv[1]
if not os.path.isdir(root):
    print("")
    sys.exit(0)

matches = []
for dirpath, _, filenames in os.walk(root):
    if "profile8.lsf" in filenames:
        path = os.path.join(dirpath, "profile8.lsf")
        matches.append(path)

if not matches:
    print("")
    sys.exit(0)

public = [p for p in matches if os.path.basename(os.path.dirname(p)).lower() == "public"]
if public:
    print(public[0])
    sys.exit(0)

matches.sort(key=lambda p: os.path.getmtime(p), reverse=True)
print(matches[0])
PY
)"
fi

if [[ -z "$PROFILE_PATH" || ! -f "$PROFILE_PATH" ]]; then
  log_error "profile8.lsf not found. Use --profile to specify the path."
  exit 1
fi

BACKUP_SUFFIX="$(date +%Y%m%d_%H%M%S)"
BACKUP_PATH="${PROFILE_PATH}.bak.${BACKUP_SUFFIX}"
cp -p "$PROFILE_PATH" "$BACKUP_PATH"
mkdir -p "$BACKUP_DIR"
BACKUP_COPY_PATH="$BACKUP_DIR/profile8.lsf.bak.${BACKUP_SUFFIX}"
cp -p "$PROFILE_PATH" "$BACKUP_COPY_PATH"
log_ok "Backup created: $BACKUP_PATH"
log_ok "Backup copy created: $BACKUP_COPY_PATH"

LSX_PATH="$WORK_DIR/profile8.lsx"
LSF_OUT="$WORK_DIR/profile8.lsf"

run_tool() {
  local input="$1"
  local output="$2"

  if [[ "$TOOL_PATH" == *.dll || "$TOOL_PATH" == *.exe ]]; then
    if ! command -v dotnet >/dev/null 2>&1; then
      echo "dotnet not found, but is required to run: $TOOL_PATH" >&2
      exit 1
    fi
    DOTNET_ROLL_FORWARD=Major dotnet "$TOOL_PATH" -a convert-resource -g bg3 -s "$input" -d "$output"
  else
    "$TOOL_PATH" -a convert-resource -g bg3 -s "$input" -d "$output"
  fi
}

log_info "Converting LSF -> LSX..."
run_tool "$PROFILE_PATH" "$LSX_PATH"

log_info "Removing DisabledSingleSaveSessions nodes..."
REMOVED_COUNT="$("$PYTHON_BIN" - "$LSX_PATH" <<'PY'
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]
tree = ET.parse(path)
root = tree.getroot()

removed = 0
for parent in root.iter():
    for child in list(parent):
        if child.tag == "node" and child.attrib.get("id") == "DisabledSingleSaveSessions":
            parent.remove(child)
            removed += 1

tree.write(path, encoding="utf-8", xml_declaration=True)
print(removed)
PY
)"

if [[ "$REMOVED_COUNT" -eq 0 ]]; then
  if [[ "$FORCE" -eq 1 ]]; then
    log_warn "No DisabledSingleSaveSessions nodes found. Continuing due to --force."
  else
    log_error "No DisabledSingleSaveSessions nodes found. Aborting to keep original safe."
    exit 1
  fi
fi

log_ok "Removed $REMOVED_COUNT node(s)."
if [[ "$REMOVED_COUNT" -gt 0 ]]; then
  echo "${C_PURPLE}${C_BOLD_ITALIC}Asterion approuves.${C_RESET}"
fi

log_info "Converting LSX -> LSF..."
run_tool "$LSX_PATH" "$LSF_OUT"

cp -p "$LSF_OUT" "$PROFILE_PATH"
log_ok "Replaced profile8.lsf successfully."
