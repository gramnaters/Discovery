#!/bin/bash
# ============================================================
#  JioHotstar Premium Patcher v3.0
#  Downloads APK from DietDroid → injects cookies → signed APK
#
#  Usage: bash scripts/patch.sh [path/to/base.apk]
#  If no APK provided, downloads automatically from DietDroid
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

# Colors
if [ -t 1 ]; then
    R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; N='\033[0m'
else
    R=''; G=''; Y=''; B=''; N=''
fi
log_i()  { echo -e "${B}[INFO]${N} $*"; }
log_ok() { echo -e "${G}[OK]${N} $*"; }
log_w()  { echo -e "${Y}[WARN]${N} $*"; }
log_e()  { echo -e "${R}[ERROR]${N} $*" >&2; }

banner() {
    echo ""
    echo -e "${G}========================================${N}"
    echo -e "${G}  JioHotstar Premium Patcher v3.0       ${N}"
    echo -e "${G}  DietDroid + CookieSeeder Pipeline     ${N}"
    echo -e "${G}========================================${N}"
    echo ""
}

check_deps() {
    log_i "Checking dependencies..."
    local missing=()
    for cmd in java apktool apksigner zipalign; do
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
    log_i "Downloading APK from DietDroid..."
    local output="$1"
    local arch="arm64-v8a"
    local ua="Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36"

    # Method 1: Merged download
    log_i "  Trying merged endpoint..."
    if curl -sS -L --max-time 300 -o "$output" \
        "https://apkdl.dietdroid.com/api/download-merged/${PKG_NAME}?arch=${arch}" 2>/dev/null; then
        local size
        size=$(stat -c%s "$output" 2>/dev/null || echo 0)
        if [ "$size" -gt 5000000 ]; then
            log_ok "  Merged download: $(du -h "$output" | cut -f1)"
            return 0
        fi
    fi
    rm -f "$output"

    # Method 2: Base APK
    log_i "  Trying base endpoint..."
    if curl -sS -L --max-time 180 -H "User-Agent: $ua" -o "$output" \
        "https://apkdl.dietdroid.com/download/${PKG_NAME}?arch=${arch}" 2>/dev/null; then
        local size
        size=$(stat -c%s "$output" 2>/dev/null || echo 0)
        if [ "$size" -gt 5000000 ]; then
            log_ok "  Base download: $(du -h "$output" | cut -f1)"
            return 0
        fi
    fi
    rm -f "$output"

    # Method 3: Individual splits (merge the ones with .so files)
    log_i "  Trying split downloads..."
    local tmp_dir
    tmp_dir=$(mktemp -d)
    local base_apk=""
    for i in 0 1 2 3 4; do
        log_i "    Split $i..."
        curl -sS -L --max-time 60 -H "User-Agent: $ua" \
            -o "$tmp_dir/split_${i}.apk" \
            "https://apkdl.dietdroid.com/download/${PKG_NAME}/${i}?arch=${arch}" 2>/dev/null || true
        if [ -f "$tmp_dir/split_${i}.apk" ]; then
            local so_count
            so_count=$(unzip -l "$tmp_dir/split_${i}.apk" 2>/dev/null | grep -c "lib/arm64.*\.so" || true)
            local fsize
            fsize=$(stat -c%s "$tmp_dir/split_${i}.apk" 2>/dev/null || echo 0)
            if [ "$fsize" -gt 5000000 ]; then
                if [ -z "$base_apk" ] || [ "$so_count" -gt 0 ]; then
                    base_apk="$tmp_dir/split_${i}.apk"
                fi
            fi
        fi
    done

    if [ -n "$base_apk" ] && [ -f "$base_apk" ]; then
        # Merge all splits into one APK
        cp "$base_apk" "$output"
        for split in "$tmp_dir"/split_*.apk; do
            [ "$split" = "$base_apk" ] && continue
            [ ! -f "$split" ] && continue
            local merge_dir
            merge_dir=$(mktemp -d)
            unzip -o "$split" -d "$merge_dir" 2>/dev/null || true
            rm -rf "${merge_dir}/META-INF"
            (cd "$merge_dir" && zip -r "$output" . 2>/dev/null) || true
            rm -rf "$merge_dir"
        done
        rm -rf "$tmp_dir"
        local size
        size=$(stat -c%s "$output" 2>/dev/null || echo 0)
        if [ "$size" -gt 5000000 ]; then
            log_ok "  Splits merged: $(du -h "$output" | cut -f1)"
            return 0
        fi
    fi
    rm -rf "$tmp_dir"
    rm -f "$output"
    log_e "All download methods failed"
    exit 1
}

find_apk() {
    if [ -z "$BASE_APK" ]; then
        # Check if base.apk exists in project root or scripts dir
        for candidate in "${PROJECT_ROOT}/base.apk" "${SCRIPT_DIR}/base.apk"; do
            if [ -f "$candidate" ] && [ -s "$candidate" ]; then
                BASE_APK="$candidate"
                log_i "Using existing: $BASE_APK ($(du -h "$BASE_APK" | cut -f1))"
                return
            fi
        done
        # Auto-download
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
    # Also extract arm64 libs if present
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

    # Remove split flags
    for attr in isSplitRequired requiredSplitTypes splitTypes intentMatchingFlags; do
        if grep -q "android:${attr}" "$manifest" 2>/dev/null; then
            sed -i "s/ android:${attr}=\"[^\"]*\"//g" "$manifest"
            log_ok "  Removed: ${attr}"
            fixes=$((fixes + 1))
        fi
    done

    # Remove split meta-data
    if grep -q "com.android.vending.splits" "$manifest" 2>/dev/null; then
        sed -i '/com.android.vending.splits/d' "$manifest"
        log_ok "  Removed: splits meta-data"
        fixes=$((fixes + 1))
    fi

    # Fix extractNativeLibs
    if grep -q 'extractNativeLibs="false"' "$manifest" 2>/dev/null; then
        sed -i 's/extractNativeLibs="false"/extractNativeLibs="true"/g' "$manifest"
        log_ok "  Fixed: extractNativeLibs=true"
        fixes=$((fixes + 1))
    fi

    # Fix @null drawables (the bug: glob doesn't match res/drawable without suffix)
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
    # Find the smallest smali dir (least files = best place for new classes)
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

    # Fallback: search by class name
    if [ -z "$full_path" ]; then
        local class_name="${app_class##*.}"
        full_path=$(find "${DECOMPILED_DIR}" -path "*/smali*" -name "${class_name}.smali" -type f 2>/dev/null | head -1)
    fi
    [ -z "$full_path" ] && { log_e "Application smali not found"; exit 1; }
    log_i "  Found: $full_path"

    # Skip if already patched
    grep -q "CookieSeeder" "$full_path" 2>/dev/null && { log_w "  Already patched, skipping"; return; }

    local inject='    invoke-static {p0}, Lcom/hotstar/patch/CookieSeeder;->seedIfNeeded(Landroid/content/Context;)V'

    if grep -q "invoke-super.*attachBaseContext" "$full_path"; then
        sed -i "/invoke-super.*attachBaseContext/a\\${inject}" "$full_path"
        log_ok "  Patched after attachBaseContext"
    elif grep -q "invoke-super.*onCreate" "$full_path"; then
        sed -i "/invoke-super.*onCreate/a\\${inject}" "$full_path"
        log_ok "  Patched after onCreate"
    else
        # Strategy: after first invoke-super
        sed -i '0,/invoke-super/{s/invoke-super.*/&\n'"${inject}"'/}' "$full_path"
        log_ok "  Patched after first super call"
    fi

    grep -q "CookieSeeder" "$full_path" && log_ok "  Verified OK" || { log_e "  Patch verification FAILED"; exit 1; }
}

patch_identity_repo() {
    log_i "Patching IdentityRepository (LDf/d)..."
    local id_file=""
    for smali_dir in "${DECOMPILED_DIR}"/smali*/; do
        if [ -f "${smali_dir}Df/d.smali" ]; then
            id_file="${smali_dir}Df/d.smali"
            break
        fi
    done
    [ -z "$id_file" ] && { log_e "  IdentityRepository (Df/d.smali) NOT FOUND"; exit 1; }
    log_i "  Found: $id_file"

    # Skip if already patched
    grep -q "CookieSeeder" "$id_file" 2>/dev/null && { log_w "  Already patched, skipping"; return; }

    local tmp="${WORK_DIR}/patched_id.smali"
    awk '
    BEGIN { in_i = 0; in_d = 0; in_ann = 0; first_inst = 0; }

    # --- Method i(): getUserToken ---
    /\.method public final i\(Lot\/d;\)Ljava\/lang\/Object;/ {
        in_i = 1; in_d = 0; in_ann = 0; first_inst = 0
        print; next
    }
    in_i == 1 {
        if (/\.locals 1$/) { sub(/\.locals 1$/, ".locals 2"); print; next }
        if (/\.annotation build/) { in_ann = 1 }
        if (/\.end annotation/) { in_ann = 0 }
        if (/^\s*\.line [0-9]+\s*$/ && first_inst == 0 && !in_ann) { next }
        if (/iget-object v0, p0, LDf\/d;->a:Ljava\/lang\/String;/ && first_inst == 0) {
            first_inst = 1
            print ""
            print "    # === PATCH: Inject user token when field a is null ==="
            print "    iget-object v0, p0, LDf/d;->a:Ljava/lang/String;"
            print "    if-nez v0, :patch_orig_i"
            print ""
            print "    invoke-static {}, Lcom/hotstar/patch/CookieSeeder;->getInjectedUserToken()Ljava/lang/String;"
            print "    move-result-object v1"
            print "    if-eqz v1, :patch_orig_i"
            print ""
            print "    iput-object v1, p0, LDf/d;->a:Ljava/lang/String;"
            print "    return-object v1"
            print ""
            print "    :patch_orig_i"
            print ""
        }
        if (/^\.end method/) { in_i = 0 }
        print; next
    }

    # --- Method d(): getMediaToken ---
    /\.method public final d\(Lwe\/J;\)Ljava\/lang\/Object;/ {
        in_d = 1; in_i = 0; in_ann = 0; first_inst = 0
        print; next
    }
    in_d == 1 {
        if (/\.locals 1$/) { sub(/\.locals 1$/, ".locals 2"); print; next }
        if (/\.annotation build/) { in_ann = 1 }
        if (/\.end annotation/) { in_ann = 0 }
        if (/^\s*\.line [0-9]+\s*$/ && first_inst == 0 && !in_ann) { next }
        if (/iget-object v0, p0, LDf\/d;->g:Ljava\/lang\/String;/ && first_inst == 0) {
            first_inst = 1
            print ""
            print "    # === PATCH: Inject media token when field g is null ==="
            print "    iget-object v0, p0, LDf/d;->g:Ljava/lang/String;"
            print "    if-nez v0, :patch_orig_d"
            print ""
            print "    invoke-static {}, Lcom/hotstar/patch/CookieSeeder;->getInjectedMediaToken()Ljava/lang/String;"
            print "    move-result-object v1"
            print "    if-eqz v1, :patch_orig_d"
            print ""
            print "    iput-object v1, p0, LDf/d;->g:Ljava/lang/String;"
            print "    return-object v1"
            print ""
            print "    :patch_orig_d"
            print ""
        }
        if (/^\.end method/) { in_d = 0 }
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
    log_i "  No native libs in rebuilt APK - downloading arm64 split..."
    local lib_tmp="${WORK_DIR}/arm64_tmp"
    rm -rf "$lib_tmp"
    mkdir -p "$lib_tmp"
    local lib_found=false
    for i in 0 1 2 3 4; do
        curl -sS -L --max-time 60 -o "$lib_tmp/split_${i}.apk" \
            "https://apkdl.dietdroid.com/download/${PKG_NAME}/${i}?arch=arm64-v8a" 2>/dev/null || true
        if [ -f "$lib_tmp/split_${i}.apk" ]; then
            local so_count
            so_count=$(unzip -l "$lib_tmp/split_${i}.apk" 2>/dev/null | grep -c "lib/arm64.*\.so" || true)
            if [ "$so_count" -gt 0 ]; then
                log_i "    Split $i has $so_count .so files - merging"
                unzip -o "$lib_tmp/split_${i}.apk" "lib/*" -d "$lib_tmp" 2>/dev/null || true
                lib_found=true
                break
            fi
        fi
    done
    if [ "$lib_found" = true ]; then
        local unsigned="${BUILD_DIR}/unsigned.apk"
        cp "$PATCHED_APK" "$unsigned"
        # Remove old signatures
        zip -d "$unsigned" "META-INF/MANIFEST.MF" "META-INF/*.SF" "META-INF/*.RSA" "META-INF/*.MF" 2>/dev/null || true
        # Add native libs
        (cd "$lib_tmp" && zip -r "$unsigned" lib/ 2>/dev/null)
        rm -rf "$lib_tmp"
        # Realign and sign
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
    else
        rm -rf "$lib_tmp"
        log_w "  Could not download arm64 libs - app may crash"
    fi
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
