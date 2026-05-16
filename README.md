# JioHotstar Premium

[![Download](https://img.shields.io/badge/Download-Latest_Release-0A0A0A?style=flat&logo=github)](https://github.com/gramnaters/Discovery/releases/latest)

Automated JioHotstar APK patcher — injects premium cookies, no root required.

## Setup

1. Fork this repo
2. Add cookies to `cookies/*.txt` (from a logged-in device)
3. Push — build runs automatically

## Builds

| Trigger | Creates Release |
|---------|:---------------:|
| Push to `main` | No |
| Daily 06:00 UTC | Yes |
| Manual (`Actions > Build > Run workflow`) | Yes |

Downloads at **GitHub Releases** (permanent) and **Actions Artifacts** (7 days).

## Files

- `cookies/` — your auth tokens
- `patches/` — smali patches
- `.github/workflows/build.yml` — pipeline
