# JioHotstar Premium AutoBuild

<p align="center">
  <img src="https://img.shields.io/badge/Package-in.startv.hotstar-blue" alt="Package">
  <img src="https://img.shields.io/badge/Arch-arm64--v8a-green" alt="Architecture">
  <img src="https://img.shields.io/badge/Root-Not_Required-success" alt="Root">
  <img src="https://img.shields.io/badge/AutoBuild-GitHub_Actions-orange" alt="CI/CD">
  <img src="https://img.shields.io/badge/Source-DietDroid-purple" alt="APK Source">
</p>

[![View Latest Release](https://img.shields.io/badge/View%20Latest%20Release-0A0A0A?style=flat&logo=github&logoColor=white)](https://github.com/gramnaters/Discovery/releases/latest)
[![Report Bug](https://img.shields.io/badge/Report%20Bug-0A0A0A?style=flat&logo=github&logoColor=white)](https://github.com/gramnaters/Discovery/issues)
[![Request Feature](https://img.shields.io/badge/Request%20Feature-0A0A0A?style=flat&logo=github&logoColor=white)](https://github.com/gramnaters/Discovery/issues)

**Automated JioHotstar patcher — builds a ready-to-install premium APK with cookie injection.**  
No root required. No manual login. Runs entirely on GitHub Actions.

---

## Setup

1. **Fork** this repository
2. **Add your cookies** — edit `.txt` files in `cookies/`:
   - `sessionUserUP.txt` — JWT user token
   - `userHID.txt` — Hardware ID
   - `userPID.txt` — Platform ID
   - `deviceId.txt` — Device ID
   - `media_token.txt` — Media token (optional)
3. **Push to main** — a build triggers automatically

## Download

| Source | Link |
|--------|------|
| **GitHub Releases** | [Download Latest](https://github.com/gramnaters/Discovery/releases/latest) |
| **Actions Artifacts** | `Actions > Build > Artifacts` (expires in 7 days) |

## Build Triggers

| Trigger | Action | Creates Release? |
|---------|--------|:----------------:|
| Push to `main` | Cookie/patch updates | No |
| Daily 06:00 UTC | Auto-rebuild | Yes |
| Manual | `Actions > Build > Run workflow` | Yes |

## Configuration

Edit files inside `cookies/` and `patches/` to customize the build. Push changes to `main` — the workflow handles the rest.

## Repository

```
.github/workflows/build.yml   — CI/CD pipeline
cookies/                       — Auth tokens (you edit these)
patches/                       — Smali patches
scripts/                       — Build utilities
```

## Local Build

```bash
# Prerequisites: Java 17+, apktool, apksigner, zipalign
bash scripts/fetch-apk.sh base.apk
bash scripts/patch.sh
```

Output: `scripts/build/jiohotstar_patched.apk`

## Troubleshooting

- **"App not installed"** — Uninstall all JioHotstar variants first
- **App crashes on launch** — Verify cookies contain valid values
- **No premium** — Check `sessionUserUP.txt` has a valid JWT
- **Download fails** — Retry later or provide your own `base.apk`

## License

This project is for educational purposes only. Use at your own risk.
