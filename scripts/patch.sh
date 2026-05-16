#!/bin/bash
# ============================================================
#  JioHotstar Premium Patcher v3.1
#  Downloads APK from gplay-apk-downloader -> injects cookies -> signed APK
#
#  Usage: bash scripts/patch.sh [path/to/base.apk]
#  If no APK provided, downloads automatically via gplay-apk-downloader
#
#  Requires: python3, curl, java, apktool, apksigner, zipalign
# ============================================================

set -uo pipefail

# Android build tools
[ -d "/tmp/android-tools/android-14" ] && export PATH="/tmp/android-tools/android-14:${PATH}"
[ -n "${ANDROID_HOME:-}" ] && [ -d "$ANDROID_HOME/build-tools" ] && \
    export PATH="$(ls -d ${ANDROID_HOME}/build-tools/*/ 2>/dev/null | sort -V | tail -1):${PATH}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
WORK_DIR="${BUILD_DIR}/work"
DECOMPILED_DIR="${WORK_DIR}/decompiled"
PATCHED_APK="${BUILD_DIR}/jiohotstar_patched.apk"
KEYSTORE="${BUILD_DIR}/sign.keystore"
KEYSTORE_PASS="hotstarpatch"
KEY_ALIAS="hotstar"
BASE_APK="${1:-}"
PKG_NAME="in.startv.hotstar"
ARCH="arm64-v8a"

# gplay-apk-downloader API (self-hosted replacement for DietDroid)
APK_DL_API="${APK_DL_API:-https://gplay-apk-downloader-zyuj.onrender.com}"

# Colors
if [ -t 1 ]; then
    R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; N='\033[0m'
else
    R=''; G=''; Y=''; B=''; N=''
fi
log_i()  { echo -e "${B}[INFO]${N} $*"; }
log_ok() { echo -e "${G}[OK]${N} $*"; }
log_w()  { echo -e "${Y}[WARN]${N} $*" >&2; }
log_e()  { echo -e "${R}[ERROR]${N} $*" >&2; }

banner() {
    echo ""
    echo -e "${G}========================================${N}"
    echo -e "${G}  JioHotstar Premium Patcher v3.1       ${N}"
    echo -e "${G}  gplay-apk-downloader + CookieSeeder   ${N}"
    echo -e "${G}========================================${N}"
    echo ""
}

check_deps() {
    log_i "Checking dependencies..."
    local missing=()
    for cmd in java apktool apksigner zipalign curl python3; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if [ ${#missing[@]} -ne 0 ]; then
        log_e "Missing: ${missing[*]}"
        exit 1
    fi
    log_ok "All dependencies available"
}

validate_cookies() {
    log_i "Validating cookie files..."
    local dir="${PROJECT_ROOT}/cookies"
    local req_files=("sessionUserUP.txt" "userHID.txt" "userPID.txt" "deviceId.txt")
    local missing=() empty=()
    for f in "${req_files[@]}"; do
        if [ ! -f "$dir/$f" ]; then missing+=("$f")
        elif [ ! -s "$dir/$f" ]; then empty+=("$f"); fi
    done
    [ ${#missing[@]} -ne 0 ] && { log_e "Missing cookies: ${missing[*]}"; exit 1; }
    [ ${#empty[@]} -ne 0 ] && { log_e "Empty cookies: ${empty[*]}"; exit 1; }
    if [ ! -s "$dir/media_token.txt" ]; then
        log_w "media_token.txt is empty - app will fetch from API"
        : > "$dir/media_token.txt"
    fi
    log_ok "Cookie files OK"
    for f in sessionUserUP userHID userPID deviceId media_token; do
        echo "  - ${f}.txt: $(wc -c < "$dir/${f}.txt") bytes"
    done
}

download_apk() {
    local output="$1"
    log_i "Downloading APK from gplay-apk-downloader..."
    log_i "  API: ${APK_DL_API}"

    python3 << PYEOF
import json, subprocess, sys, time, os

API = os.environ.get('APK_DL_API', '${APK_DL_API}')
PKG = '${PKG_NAME}'
ARCH = '${ARCH}'
OUTPUT = '${output}'

def parse_sse(endpoint, max_wait=180):
    """Call an SSE endpoint and return the first success event."""
    proc = subprocess.Popen(
        ['curl', '-sN', '--max-time', str(max_wait), endpoint],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    success_data = None
    start = time.time()
    for line in proc.stdout:
        line = line.strip()
        if not line:
            continue
        if line.startswith('data: '):
            try:
                data = json.loads(line[6:])
                if data.get('type') == 'progress':
                    msg = data.get('message', '')
                    step = data.get('step', '')
                    print(f"    [{step}] {msg}", flush=True)
                elif data.get('type') == 'success':
                    success_data = data
                    break
            except json.JSONDecodeError:
                pass
        if time.time() - start > max_wait:
            print("    [TIMEOUT] Max wait exceeded", flush=True)
            break
    proc.terminate()
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()
    return success_data

def download_file(url, out_path, cookie_str="", max_time=300):
    """Download a file with optional cookie header."""
    cmd = ['curl', '-sS', '-L', '--max-time', str(max_time), '-o', out_path]
    if cookie_str:
        cmd += ['-H', f'Cookie: {cookie_str}']
    cmd.append(url)
    result = subprocess.run(cmd, capture_output=True, text=True)
    return os.path.exists(out_path) and os.path.getsize(out_path) > 0

# Method 1: Merged download (server-side merge+sign)
print("\n  Method 1: Merged download via SSE stream...", flush=True)
merged = parse_sse(f"{API}/api/download-merged-stream/{PKG}?arch={ARCH}", max_wait=300)

if merged and merged.get('download_id'):
    dl_id = merged['download_id']
    print(f"    Got download_id: {dl_id}", flush=True)
    print(f"    Downloading merged APK...", flush=True)
    if download_file(f"{API}/api/download-temp/{dl_id}", OUTPUT):
        size = os.path.getsize(OUTPUT)
        if size > 5000000:
            print(f"    SUCCESS: {size / 1024 / 1024:.1f} MB", flush=True)
            sys.exit(0)
        else:
            print(f"    Merged APK too small ({size} bytes)", flush=True)
    else:
        print(f"    Failed to download from temp endpoint", flush=True)
else:
    print(f"    Merged endpoint did not return download_id", flush=True)

if os.path.exists(OUTPUT):
    os.remove(OUTPUT)

# Method 2: Direct CDN download via info stream
print("\n  Method 2: Direct CDN download via info stream...", flush=True)
info = parse_sse(f"{API}/api/download-info-stream/{PKG}?arch={ARCH}", max_wait=120)

if not info:
    print("ERROR: Failed to get download info from API", flush=True)
    sys.exit(1)

dl_url = info.get('downloadUrl')
cookies_list = info.get('cookies', [])
cookie_str = '; '.join([f"{c['name']}={c['value']}" for c in cookies_list]) if cookies_list else ''
splits = info.get('splits', [])

print(f"    App: {info.get('title', PKG)}", flush=True)
print(f"    Version: {info.get('version')} (code: {info.get('versionCode')})", flush=True)
print(f"    Base: {info.get('filename')} ({info.get('size')})", flush=True)
print(f"    Splits: {len(splits)}", flush=True)

if not dl_url:
    print("ERROR: No download URL in info response", flush=True)
    sys.exit(1)

print(f"\n    Downloading base APK from Google CDN...", flush=True)
if not download_file(dl_url, OUTPUT, cookie_str, 300):
    print("ERROR: Base APK download failed", flush=True)
    sys.exit(1)

size = os.path.getsize(OUTPUT)
if size < 1000000:
    print(f"ERROR: Base APK too small ({size} bytes)", flush=True)
    sys.exit(1)

print(f"    SUCCESS: Base APK {size / 1024 / 1024:.1f} MB", flush=True)

# Pre-download arm64 split for later native lib injection
for split in splits:
    if 'arm64' in split.get('name', '').lower():
        split_url = split.get('downloadUrl')
        if split_url:
            arm64_path = os.path.join(os.path.dirname(OUTPUT), 'arm64_split.apk')
            print(f"\n    Pre-downloading arm64 split ({split.get('name')})...", flush=True)
            if download_file(split_url, arm64_path, cookie_str, 300):
                print(f"    Arm64 split saved: {os.path.getsize(arm64_path) / 1024 / 1024:.1f} MB", flush=True)
            else:
                print(f"    WARNING: Arm64 split download failed", flush=True)
        break

PYEOF
    local result=$?
    if [ $result -ne 0 ]; then
        log_e "APK download failed (exit code: $result)"
        exit 1
    fi
    if [ ! -f "$output" ] || [ ! -s "$output" ]; then
        log_e "APK download failed - no file"
        exit 1
    fi
    log_ok "Download complete: $(du -h "$output" | cut -f1)"
}

find_apk() {
    if [ -z "$BASE_APK" ]; then
        for candidate in "${PROJECT_ROOT}/base.apk" "${SCRIPT_DIR}/base.apk"; do
            if [ -f "$candidate" ] && [ -s "$candidate" ]; then
                BASE_APK="$candidate"
                log_i "Using existing: $BASE_APK ($(du -h "$BASE_APK" | cut -f1))"
                return
            fi
        done
        BASE_APK="${BUILD_DIR}/downloaded.apk"
        mkdir -p "$BUILD_DIR"
        download_apk "$BASE_APK"
    fi
    if [ ! -f "$BASE_APK" ]; then
        log_e "APK not found: $BASE_APK"; exit 1
    fi
    log_i "APK: $BASE_APK ($(du -h "$BASE_APK" | cut -f1))"
}

handle_xapk() {
    local apk="$1"
    if ! unzip -l "$apk" 2>/dev/null | grep -q "manifest.json"; then
        log_i "Format: standard APK"; return
    fi
    local manifest
    manifest=$(unzip -p "$apk" "manifest.json" 2>/dev/null | head -c 200) || true
    if ! echo "$manifest" | grep -q "xapk_version\|package_name"; then
        log_i "Format: standard APK"; return
    fi
    log_i "Detected XAPK - extracting base APK..."
    local main_apk
    main_apk=$(unzip -l "$apk" 2>/dev/null | grep '\.apk$' | awk '{print $4, $1}' | sort -k2 -rn | head -1 | awk '{print $1}')
    if [ -z "$main_apk" ]; then log_e "No APK in XAPK"; exit 1; fi
    local extracted="${WORK_DIR}/xapk_extracted"
    mkdir -p "$extracted"
    unzip -o "$apk" "$main_apk" -d "$extracted" 2>/dev/null
    BASE_APK="${extracted}/${main_apk}"
    for f in $(unzip -l "$apk" 2>/dev/null | grep 'config.arm64.*\.apk' | awk '{print $4}'); do
        log_i "  Extracting arm64 split: $f"
        unzip -o "$apk" "$f" -d "$extracted" 2>/dev/null
    done
    log_i "  Base APK: $(du -h "$BASE_APK" | cut -f1)"
}

decompile() {
    log_i "Decompiling APK..."
    rm -rf "${DECOMPILED_DIR}"
    mkdir -p "${WORK_DIR}"
    if ! apktool d "$BASE_APK" -o "${DECOMPILED_DIR}" -f 2>&1 | tee "${WORK_DIR}/decompile.log"; then
        log_e "Decompile failed"; exit 1
    fi
    log_ok "Decompiled OK"
}

fix_manifest() {
    log_i "Fixing manifest and resources..."
    local manifest="${DECOMPILED_DIR}/AndroidManifest.xml"
    local fixes=0

    for attr in isSplitRequired requiredSplitTypes splitTypes intentMatchingFlags; do
        if grep -q "android:${attr}" "$manifest" 2>/dev/null; then
            sed -i "s/ android:${attr}=\"[^\"]*\"//g" "$manifest"
            log_ok "  Removed: ${attr}"
            fixes=$((fixes + 1))
        fi
    done

    if grep -q "com.android.vending.splits" "$manifest" 2>/dev/null; then
        sed -i '/com.android.vending.splits/d' "$manifest"
        log_ok "  Removed: splits meta-data"
        fixes=$((fixes + 1))
    fi

    if grep -q 'extractNativeLibs="false"' "$manifest" 2>/dev/null; then
        sed -i 's/extractNativeLibs="false"/extractNativeLibs="true"/g' "$manifest"
        log_ok "  Fixed: extractNativeLibs=true"
        fixes=$((fixes + 1))
    fi

    local null_count=0
    for ddir in "${DECOMPILED_DIR}/res/"drawable*; do
        [ -d "$ddir" ] || continue
        while IFS= read -r -d '' f; do
            if grep -q 'android:drawable="@null"' "$f" 2>/dev/null; then
                sed -i 's/android:drawable="@null"/android:drawable="@android:color\/transparent"/g' "$f"
                null_count=$((null_count + 1))
            fi
        done < <(find "$ddir" -name "*.xml" -type f -print0 2>/dev/null)
    done
    [ "$null_count" -gt 0 ] && log_ok "  Fixed $null_count drawable files: @null -> transparent"
    [ "$fixes" -eq 0 ] && [ "$null_count" -eq 0 ] && log_i "  Nothing to fix"
}

inject_smali() {
    log_i "Injecting smali patches..."
    local smallest_dir="" smallest_count=999999
    for dir in "${DECOMPILED_DIR}"/smali*/; do
        [ -d "$dir" ] || continue
        local count
        count=$(find "$dir" -name "*.smali" -type f 2>/dev/null | wc -l)
        if [ "$count" -lt "$smallest_count" ]; then
            smallest_count=$count
            smallest_dir="$dir"
        fi
    done
    [ -z "$smallest_dir" ] && { log_e "No smali dirs found"; exit 1; }
    [ ! -d "$smallest_dir" ] && { log_e "Smali dir not found"; exit 1; }

    local target="${smallest_dir}com/hotstar/patch"
    mkdir -p "$target"
    cp "${PROJECT_ROOT}/patches/CookieFileReader.smali" "${target}/CookieFileReader.smali"
    cp "${PROJECT_ROOT}/patches/cookie-seeder.smali" "${target}/CookieSeeder.smali"
    log_ok "  Injected into $target (${smallest_count} file dir)"
}

inject_assets() {
    log_i "Injecting cookie assets..."
    local assets="${DECOMPILED_DIR}/assets/cookies"
    mkdir -p "$assets"
    for f in "${PROJECT_ROOT}/cookies"/*.txt; do
        [ -f "$f" ] || continue
        cp "$f" "${assets}/$(basename "$f")"
        log_ok "  $(basename "$f") -> assets/cookies/"
    done
}

patch_app_class() {
    log_i "Patching Application class..."
    local manifest="${DECOMPILED_DIR}/AndroidManifest.xml"
    local app_class
    app_class=$(grep -oP '<application\s[^>]*android:name="\K[^"]+' "$manifest")
    [ -z "$app_class" ] && { log_e "No Application class found"; exit 1; }
    log_i "  Class: $app_class"

    local smali_path="${app_class//./\/}.smali"
    local full_path=""
    for smali_dir in "${DECOMPILED_DIR}"/smali*/; do
        [ -f "${smali_dir}${smali_path}" ] && { full_path="${smali_dir}${smali_path}"; break; }
    done
    if [ -z "$full_path" ]; then
        local class_name="${app_class##*.}"
        full_path=$(find "${DECOMPILED_DIR}" -path "*/smali*" -name "${class_name}.smali" -type f 2>/dev/null | head -1)
    fi
    [ -z "$full_path" ] && { log_e "Application smali not found"; exit 1; }
    log_i "  Found: $full_path"

    grep -q "CookieSeeder" "$full_path" 2>/dev/null && { log_w "  Already patched, skipping"; return; }

    local inject='    invoke-static {p0}, Lcom/hotstar/patch/CookieSeeder;->seedIfNeeded(Landroid/content/Context;)V'

    local line_num
    line_num=$(grep -n "invoke-super" "$full_path" | head -1 | cut -d: -f1)
    if [ -n "$line_num" ]; then
        sed -i "${line_num}a\\${inject}" "$full_path"
        log_ok "  Patched after invoke-super (line $line_num)"
    else
        log_e "  No invoke-super found in Application class"
        exit 1
    fi

    grep -q "CookieSeeder" "$full_path" && log_ok "  Verified OK" || { log_e "  Patch verification FAILED"; exit 1; }
}

patch_identity_repo() {
    log_i "Patching IdentityRepository (LFf/d)..."
    local id_file=""
    for smali_dir in "${DECOMPILED_DIR}"/smali*/; do
        if [ -f "${smali_dir}Ff/d.smali" ]; then
            id_file="${smali_dir}Ff/d.smali"
            break
        fi
    done
    [ -z "$id_file" ] && { log_w "  IdentityRepository (Ff/d.smali) NOT FOUND - skipping"; return; }
    log_i "  Found: $id_file"

    grep -q "CookieSeeder" "$id_file" 2>/dev/null && { log_w "  Already patched, skipping"; return; }

    local tmp="${WORK_DIR}/patched_id.smali"
    awk '
    BEGIN { in_c = 0; in_i = 0; in_ann = 0; first_inst = 0; }

    /\.method public final c\(Ltt\/d;\)Ljava\/lang\/Object;/ {
        in_c = 1; in_i = 0; in_ann = 0; first_inst = 0
        print; next
    }
    in_c == 1 {
        if (/\.locals [0-9]+$/) { n=$2+0; if(n<2) sub(/\.locals [0-9]+$/, ".locals 2") }
        if (/\.registers [0-9]+$/) { n=$2+0; if(n<4) sub(/\.registers [0-9]+$/, ".registers 4") }
        if (/\.locals [0-9]+$/ || /\.registers [0-9]+$/) { print; next }
        if (/\.annotation build/) { in_ann = 1 }
        if (/\.end annotation/) { in_ann = 0 }
        if (/^\s*\.line [0-9]+\s*$/ && first_inst == 0 && !in_ann) { next }
        if (/iget-object v0, p0, LFf\/d;->a:Ljava\/lang\/String;/ && first_inst == 0) {
            first_inst = 1
            print ""
            print "    # === PATCH: Inject user token when field a is null ==="
            print "    iget-object v0, p0, LFf/d;->a:Ljava/lang/String;"
            print "    if-nez v0, :patch_orig_c"
            print ""
            print "    invoke-static {}, Lcom/hotstar/patch/CookieSeeder;->getInjectedUserToken()Ljava/lang/String;"
            print "    move-result-object v1"
            print "    if-nez v1, :patch_orig_c"
            print ""
            print "    iput-object v1, p0, LFf/d;->a:Ljava/lang/String;"
            print "    return-object v1"
            print ""
            print "    :patch_orig_c"
            print ""
            next
        }
        if (/^\.end method/) { in_c = 0 }
        print; next
    }

    /\.method public final i\(Lye\/J;\)Ljava\/lang\/Object;/ {
        in_i = 1; in_c = 0; in_ann = 0; first_inst = 0
        print; next
    }
    in_i == 1 {
        if (/\.locals [0-9]+$/) { n=$2+0; if(n<2) sub(/\.locals [0-9]+$/, ".locals 2") }
        if (/\.registers [0-9]+$/) { n=$2+0; if(n<4) sub(/\.registers [0-9]+$/, ".registers 4") }
        if (/\.locals [0-9]+$/ || /\.registers [0-9]+$/) { print; next }
        if (/\.annotation build/) { in_ann = 1 }
        if (/\.end annotation/) { in_ann = 0 }
        if (/^\s*\.line [0-9]+\s*$/ && first_inst == 0 && !in_ann) { next }
        if (/iget-object v0, p0, LFf\/d;->g:Ljava\/lang\/String;/ && first_inst == 0) {
            first_inst = 1
            print ""
            print "    # === PATCH: Inject media token when field g is null ==="
            print "    iget-object v0, p0, LFf/d;->g:Ljava/lang/String;"
            print "    if-nez v0, :patch_orig_i"
            print ""
            print "    invoke-static {}, Lcom/hotstar/patch/CookieSeeder;->getInjectedMediaToken()Ljava/lang/String;"
            print "    move-result-object v1"
            print "    if-nez v1, :patch_orig_i"
            print ""
            print "    iput-object v1, p0, LFf/d;->g:Ljava/lang/String;"
            print "    return-object v1"
            print ""
            print "    :patch_orig_i"
            print ""
            next
        }
        if (/^\.end method/) { in_i = 0 }
        print; next
    }

    { print }
    ' "$id_file" > "$tmp"

    [ ! -s "$tmp" ] && { log_e "  AWK produced empty output"; exit 1; }
    mv "$tmp" "$id_file"

    grep -q "getInjectedUserToken" "$id_file" && log_ok "  getUserToken patch: OK" || { log_e "  getUserToken patch FAILED"; exit 1; }
    grep -q "getInjectedMediaToken" "$id_file" && log_ok "  getMediaToken patch: OK" || { log_e "  getMediaToken patch FAILED"; exit 1; }
}

recompile() {
    log_i "Recompiling APK..."
    rm -f "$PATCHED_APK"
    if ! apktool b "${DECOMPILED_DIR}" -o "$PATCHED_APK" 2>&1 | tee "${WORK_DIR}/recompile.log"; then
        log_e "Recompile failed"
        tail -10 "${WORK_DIR}/recompile.log" 2>/dev/null
        exit 1
    fi
    [ ! -f "$PATCHED_APK" ] && { log_e "Output APK missing"; exit 1; }
    log_ok "Recompiled: $(du -h "$PATCHED_APK" | cut -f1)"
}

inject_native_libs() {
    log_i "Checking native libraries..."
    local has_libs
    has_libs=$(unzip -l "$PATCHED_APK" 2>/dev/null | grep -c "lib/arm64.*\.so" || true)
    if [ "$has_libs" -gt 0 ]; then
        log_ok "  Native libs present ($has_libs .so files)"
        return
    fi

    log_i "  No native libs in rebuilt APK - looking for arm64 split..."

    # Check if arm64 split was pre-downloaded by download_apk()
    local lib_source=""
    if [ -f "${BUILD_DIR}/arm64_split.apk" ] && [ "$(stat -c%s "${BUILD_DIR}/arm64_split.apk" 2>/dev/null || echo 0)" -gt 1000000 ]; then
        local so_count
        so_count=$(unzip -l "${BUILD_DIR}/arm64_split.apk" 2>/dev/null | grep -c "lib/arm64.*\.so" || true)
        if [ "$so_count" -gt 0 ]; then
            log_i "    Using pre-downloaded arm64 split ($so_count .so files)"
            lib_source="${BUILD_DIR}/arm64_split.apk"
        fi
    fi

    # Fallback: download from API
    if [ -z "$lib_source" ]; then
        log_i "    Downloading arm64 split from API..."
        local tmp_dir
        tmp_dir=$(mktemp -d)
        python3 -c "
import json, subprocess, sys, time, os
API = '${APK_DL_API}'
PKG = '${PKG_NAME}'
ARCH = '${ARCH}'
proc = subprocess.Popen(['curl', '-sN', '--max-time', '120', f'{API}/api/download-info-stream/{PKG}?arch={ARCH}'],
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
success = None
for line in proc.stdout:
    line = line.strip()
    if line.startswith('data: '):
        try:
            d = json.loads(line[6:])
            if d.get('type') == 'success':
                success = d
                break
        except: pass
proc.terminate(); proc.wait(timeout=10)
if success:
    cookies = success.get('cookies', [])
    cookie_str = '; '.join([f\"{c['name']}={c['value']}\" for c in cookies])
    for s in success.get('splits', []):
        if 'arm64' in s.get('name', '').lower():
            url = s.get('downloadUrl', '')
            if url:
                cmd = ['curl', '-sS', '-L', '--max-time', '300', '-o', '${tmp_dir}/arm64.apk']
                if cookie_str:
                    cmd += ['-H', f'Cookie: {cookie_str}']
                cmd.append(url)
                subprocess.run(cmd)
                break
" 2>/dev/null

        if [ -f "${tmp_dir}/arm64.apk" ] && [ "$(stat -c%s "${tmp_dir}/arm64.apk" 2>/dev/null || echo 0)" -gt 1000000 ]; then
            local so_count
            so_count=$(unzip -l "${tmp_dir}/arm64.apk" 2>/dev/null | grep -c "lib/arm64.*\.so" || true)
            if [ "$so_count" -gt 0 ]; then
                lib_source="${tmp_dir}/arm64.apk"
                log_i "    Downloaded arm64 split ($so_count .so files)"
            fi
        fi
        rm -rf "$tmp_dir" 2>/dev/null
    fi

    if [ -z "$lib_source" ]; then
        log_w "  Could not get arm64 split - app may crash on launch"
        return
    fi

    # Extract and inject native libs
    local lib_tmp="${WORK_DIR}/arm64_tmp"
    rm -rf "$lib_tmp"
    mkdir -p "$lib_tmp"
    log_i "    Extracting native libs..."
    unzip -o "$lib_source" "lib/*" -d "$lib_tmp" 2>/dev/null || true

    local unsigned="${BUILD_DIR}/unsigned.apk"
    cp "$PATCHED_APK" "$unsigned"
    zip -d "$unsigned" "META-INF/MANIFEST.MF" "META-INF/*.SF" "META-INF/*.RSA" "META-INF/*.MF" 2>/dev/null || true
    (cd "$lib_tmp" && zip -r "$unsigned" lib/ 2>/dev/null)
    rm -rf "$lib_tmp"

    local aligned="${BUILD_DIR}/aligned_lib.apk"
    zipalign -f 4 "$unsigned" "$aligned"
    rm -f "$unsigned"
    generate_keystore
    apksigner sign --ks "$KEYSTORE" --ks-pass "pass:${KEYSTORE_PASS}" \
        --ks-key-alias "$KEY_ALIAS" --key-pass "pass:${KEYSTORE_PASS}" \
        --out "$PATCHED_APK" "$aligned" 2>/dev/null
    rm -f "$aligned"

    local final_libs
    final_libs=$(unzip -l "$PATCHED_APK" 2>/dev/null | grep -c "lib/arm64.*\.so" || true)
    log_ok "  Injected $final_libs arm64 native libs"
}

generate_keystore() {
    [ -f "$KEYSTORE" ] && return
    log_i "Generating signing keystore..."
    keytool -genkeypair -v -keystore "$KEYSTORE" -alias "$KEY_ALIAS" -keyalg RSA \
        -keysize 2048 -validity 10000 -storepass "$KEYSTORE_PASS" -keypass "$KEYSTORE_PASS" \
        -dname "CN=Patcher, OU=Patch, O=HP, L=X, ST=X, C=XX" 2>&1 | tail -1
    log_ok "  Keystore generated"
}

sign_apk() {
    log_i "Signing APK..."
    generate_keystore
    local aligned="${BUILD_DIR}/aligned.apk"
    rm -f "$aligned"
    zipalign -f 4 "$PATCHED_APK" "$aligned"
    apksigner sign --ks "$KEYSTORE" --ks-pass "pass:${KEYSTORE_PASS}" \
        --ks-key-alias "$KEY_ALIAS" --key-pass "pass:${KEYSTORE_PASS}" \
        --out "$PATCHED_APK" "$aligned" 2>/dev/null
    rm -f "$aligned"
    apksigner verify "$PATCHED_APK" 2>/dev/null && log_ok "  Signature verified" || log_w "  Signature verify issue"
}

main() {
    banner
    check_deps
    validate_cookies
    find_apk
    mkdir -p "${BUILD_DIR}" "${WORK_DIR}"
    handle_xapk "$BASE_APK"
    decompile
    fix_manifest
    inject_smali
    inject_assets
    patch_app_class
    patch_identity_repo
    recompile
    inject_native_libs
    sign_apk
    echo ""
    echo -e "${G}========================================${N}"
    echo -e "${G}  PATCH COMPLETE!${N}"
    echo -e "${G}========================================${N}"
    echo "  APK: ${PATCHED_APK} ($(du -h "$PATCHED_APK" | cut -f1))"
    echo ""
}

main "$@"
