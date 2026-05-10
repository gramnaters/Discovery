# JioHotstar Premium AutoBuild

Automated JioHotstar premium cookie injector. Fork, add your cookies, and GitHub Actions builds a ready-to-install patched APK.

## Features

- Premium account auto-login (no manual login needed)
- No root required - works on all Android devices
- Cookie injection via DataStore seed (survives app restarts)
- Auto token refresh (server updates preserved after first inject)
- Split APK merge (standalone install, no SAI needed)
- Arm64 native lib injection
- Daily auto-build via GitHub Actions

## Quick Setup

### 1. Fork this repository

### 2. Add your cookies

Edit the files in `cookies/` with your JioHotstar account cookies:

```
cookies/
├── sessionUserUP.txt    # JWT user token (required)
├── userHID.txt          # Hardware ID (required)
├── userPID.txt          # Platform ID (required)
├── deviceId.txt         # Device ID (required)
└── media_token.txt      # Media token (optional)
```

### 3. Push to main

Any push to `main` triggers an automatic build. Or go to **Actions > Build > Run workflow** for a manual trigger.

### 4. Download

Get your patched APK from:
- **Actions > Build > Artifacts** (direct download)
- **Releases > latest** (auto-created on scheduled/manual builds)

## How to Get Cookies

1. Log into JioHotstar on a browser (Chrome/Firefox)
2. Open **DevTools** -> **Application** -> **Cookies** -> `https://www.hotstar.com`
3. Copy the values for each cookie:

| File | Cookie Name | Example |
|------|-------------|---------|
| `sessionUserUP.txt` | `sessionUserUP` | `eyJhbGciOiJIUzI1NiIs...` (long JWT) |
| `userHID.txt` | `userHID` | `acn\|282893298745332` |
| `userPID.txt` | `userPID` | `668e9374a27b4b8c9320e5da32c9a01b` |
| `deviceId.txt` | `deviceId` | `921e4d-5b3a38-767889-e36ac` |
| `media_token.txt` | `st` or `media_token` | `eyJhbGciOiJSUzI1NiIs...` |

Each `.txt` file should contain **only the raw value** - no headers, no quotes, no extra whitespace.

## How It Works

```
┌─────────────────────────────────────────────────────┐
│                   GitHub Actions                     │
│                                                      │
│  1. Download APK ---- DietDroid (Play Store CDN)    │
│  2. Decompile ------- apktool                        │
│  3. Fix splits ------ Remove isSplitRequired flags   │
│  4. Fix drawables --- @null -> transparent           │
│  5. Inject smali ---- CookieSeeder + FileReader      │
│  6. Patch IdentityRepo -- LDf/d.i() + .d()          │
│  7. Patch Application -- CookieSeeder.seedIfNeeded() │
│  8. Recompile ------- apktool build                 │
│  9. Inject libs ------ arm64-v8a native libs         │
│ 10. Sign + Align ----- apksigner + zipalign          │
│ 11. Release ---------- GitHub Release / Artifact      │
└─────────────────────────────────────────────────────┘
```

## Manual Build (Local)

```bash
# Prerequisites: java 17+, apktool, apksigner, zipalign
bash scripts/patch.sh                # auto-downloads from DietDroid
bash scripts/patch.sh my_apk.apk     # use your own APK

# Output: scripts/build/jiohotstar_patched.apk
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "App not installed" | Uninstall all JioHotstar variants first |
| App crashes on launch | Check logcat - ensure cookies have correct values |
| App launches but no premium | Verify `sessionUserUP.txt` contains a valid JWT |
| DietDroid download fails | Retry later or place APK manually as `base.apk` |

## Credits

- APK source: [DietDroid](https://apkdl.dietdroid.com/) (Google Play CDN proxy)
- Reverse engineering: smali/baksmali, apktool
