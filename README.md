<div align="center">
  <img src="https://capsule-render.vercel.app/api?type=waving&color=0:ff6b6b,100:ffa502&height=200&section=header&text=Discovery&fontSize=80&fontColor=fff&animation=fadeIn" />
</div>

# JioHotstar Premium AutoBuild

[![Telegram](https://img.shields.io/badge/Telegram-2CA5E0?style=for-the-badge&logo=telegram&logoColor=white)](https://t.me/gramnaters)
[![GitHub Release](https://img.shields.io/github/v/release/gramnaters/Discovery?style=for-the-badge&logo=github&color=ff6b6b)](https://github.com/gramnaters/Discovery/releases/latest)

> Automated JioHotstar patcher — builds a ready-to-install premium APK with cookie injection. No root required.

---

## Usage

1. **Fork** this repository
2. **Add your cookies** to `cookies/`:
   - `sessionUserUP.txt` — JWT user token
   - `userHID.txt` — Hardware ID
   - `userPID.txt` — Platform ID
   - `deviceId.txt` — Device ID
   - `media_token.txt` — Media token (optional)
3. **Push to `main`** — build runs automatically

> Cookies can be exported from a browser session logged into hotstar.com

## Downloads

| Source | Link |
|--------|------|
| **GitHub Releases** | [Download Latest](https://github.com/gramnaters/Discovery/releases/latest) |
| **Actions Artifacts** | `Actions > Build > Artifacts` (expires in 7 days) |

## Build triggers

| Trigger | Creates Release |
|---------|:---------------:|
| Push to `main` | No |
| Daily 06:00 UTC | Yes |
| Manual (`Actions > Build > Run workflow`) | Yes |

---

## License

[![GNU GPLv3](https://www.gnu.org/graphics/gplv3-127x51.png)](http://www.gnu.org/licenses/gpl-3.0.en.html)

This project is licensed under the GNU General Public License v3.0.
