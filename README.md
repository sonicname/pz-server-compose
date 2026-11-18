# Project Zomboid server (Build 42) — Docker Compose

Server Project Zomboid cho nhóm bạn nhỏ (4–8 người). Ưu tiên **ổn định**, có sẵn bộ mod QoL + gameplay đã kiểm tra tương thích **B42 stable + multiplayer**.

- Game: Build 42 stable (nhánh public từ 42.20 – 29/07/2026; hiện tại 42.22.2)
- Server tự cài/cập nhật qua SteamCMD khi container khởi động
- Danh sách mod quản lý ở **một file**: `config/mods.txt`
- Backup tự động 3 giờ/lần (giữ 24 bản ≈ 3 ngày) + backup có sẵn của game
- Tắt server an toàn: `docker compose stop` → `save` + `quit`, chờ tối đa 3 phút

## Yêu cầu

| | Tối thiểu | Khuyến nghị |
|---|---|---|
| RAM máy chủ | 4 GB + swap (heap 3g, 2–4 người) | 8 GB (heap 5g) |
| CPU | 2 nhân, xung cao | 2–4 nhân xung cao (server chủ yếu chạy 1 luồng) |
| Ổ đĩa | 15 GB | SSD |
| Mạng | Truy cập được Steam; mở **UDP 16261–16262** | |

Chạy trên Linux (VPS hoặc máy riêng) là ổn định nhất. Docker Desktop trên Windows/WSL2 vẫn chạy được nhưng khởi động chậm hơn nhiều.

## Cài đặt

```bash
cp .env.example .env        # rồi sửa mật khẩu trong .env
docker compose up -d --build
docker compose logs -f pz   # lần đầu: tải ~3-5 GB game + mod, có thể mất 10-30 phút
```

Server sẵn sàng khi log hiện `SERVER STARTED`. Bạn bè vào game → **Join** → nhập IP máy chủ, port `16261`, mật khẩu `SERVER_PASSWORD`.

### Cho bạn bè kết nối
- **VPS / IP public**: mở firewall UDP 16261–16262.
- **Máy ở nhà**: port-forward UDP 16261–16262 trên router về máy chạy server. Nếu nhà mạng dùng CGNAT (không có IP public) thì dùng **Tailscale** hoặc **ZeroTier**: cả nhóm cài, rồi join bằng IP ảo.

## Thiết lập thế giới (làm trước khi chơi thật)

Sandbox (độ khó, tần suất zombie, loot...) chỉ có tác dụng khi **tạo world mới**. Quy trình:

```bash
docker compose up -d && docker compose logs -f pz   # chờ SERVER STARTED (tạo file cấu hình)
docker compose stop pz
# Sửa các file trong volume (Windows: dùng Docker Desktop → Volumes → pz_pz-zomboid-data,
# hoặc đặt ZOMBOID_DATA=./data/zomboid trong .env trên Linux để sửa trực tiếp):
#   Server/<SERVER_NAME>_SandboxVars.lua   ← độ khó, zombie, loot
#   Server/<SERVER_NAME>.ini               ← PvP, safehouse, v.v.
# Xoá world vừa tạo thử để tạo lại với sandbox mới:
docker compose run --rm --entrypoint sh pz -c 'rm -rf /home/steam/Zomboid/Saves/Multiplayer/$SERVER_NAME'
docker compose up -d
```

> Các key trong `.ini` do `.env` quản lý (Mods, WorkshopItems, Map, Password, Public, MaxPlayers, port, RCON, SaveWorldEveryMinutes, PauseEmpty, DoLuaChecksum, Backups*) **bị ghi đè mỗi lần khởi động**. Đổi những key này trong `.env`. Các key khác bạn sửa tay thoải mái.

## Mod

Sửa `config/mods.txt`, mỗi dòng một Workshop item:

```
<workshop_id> | <mod_id>[;<mod_id>...] | <map_folder (nếu là map)>
```

Rồi `docker compose restart pz`. Entrypoint tự sinh `WorkshopItems=`, `Mods=\ModID;...` (định dạng B42) và `Map=...;Muldraugh, KY`.

**Bộ mặc định (20 item):** errorMagnifier, Mod Alert System, damnlib (thư viện) · Skill Recovery Journal, Common Sense (bản fix 42.21), Better Sorting, Has Been Read, Proximity Inventory, Equipment UI, Manage Containers, Mini Health Panel, Map Symbol Size Slider, Share Annotations, KillCount, Vehicle Repair Overhaul (QoL) · Vanilla Foods Expanded, SaucedCarts, KI5 M998 + Range Rover, Containers! (gameplay).

Tuỳ chọn có trong file (đang comment): helicopter events, True Music Radio, map Greenleaf / Muldraugh Shipping Co.

**Quy tắc để server ổn định:**
1. **Thêm mod thì dễ, gỡ mod thì nguy hiểm.** Mod đánh dấu ⚠ (xe, map, đồ đặt trong world) đặt object vào save. Gỡ giữa chừng có thể làm hỏng cell/xe. Luôn backup trước khi gỡ.
2. **Map mod nên thêm trước khi tạo world.** Thêm sau thì chỉ có tác dụng ở những ô chưa ai đến.
3. Mod Workshop tự cập nhật khi server restart (không khoá phiên bản được). Khi tác giả mod cập nhật, client sẽ báo lệch phiên bản. Lúc đó restart server: `docker compose restart pz`.
4. Kiểm tra mod có cập nhật chưa: `docker compose exec pz pz-rcon checkModsNeedUpdate`, rồi xem `docker compose logs pz`.
5. Không bật cùng lúc các cặp xung đột (ghi ở cuối `mods.txt`). Tránh Tsar's Common Library / Autotsar trên server Linux (đang có lỗi đường dẫn phân biệt hoa thường).

## Vận hành hằng ngày

| Việc | Lệnh |
|---|---|
| Xem log | `docker compose logs -f pz` |
| Restart (cập nhật game + mod) | `docker compose restart pz` |
| Dừng an toàn | `docker compose stop` |
| Lệnh admin | `docker compose exec pz pz-rcon players` · `... pz-rcon save` · `... pz-rcon "servermsg \"Restart sau 5 phut\""` |
| Backup ngay | `docker compose run --rm backup backup once` |

Khi game có bản cập nhật, Steam của mọi người tự cập nhật, còn server phải restart mới cập nhật theo (`AUTO_UPDATE=true`). Nếu mod chưa theo kịp bản game mới, đặt `AUTO_UPDATE=false` và nhắc cả nhóm tạm giữ phiên bản cũ.

## Khôi phục backup

```bash
docker compose stop pz
ls backups/                                   # chọn bản muốn khôi phục
docker compose run --rm -v "$PWD/backups:/restore:ro" --entrypoint sh pz -c '
  cd /home/steam/Zomboid &&
  rm -rf "Saves/Multiplayer/$SERVER_NAME" &&
  tar -xzf /restore/<TÊN_FILE>.tar.gz &&
  chown -R steam:steam /home/steam/Zomboid'
docker compose up -d
```

## Xử lý sự cố

| Triệu chứng | Cách xử lý |
|---|---|
| Không tải được game/mod, SteamCMD lỗi | Máy chủ phải truy cập được Steam. Có mạng chặn Steam (lỗi TLS/`SSL_ERROR_SYSCALL`). |
| Bạn bè bị kick vì checksum | Mọi người unsubscribe rồi subscribe lại mod / verify files. Nếu vẫn lỗi dù mod khớp: `LUA_CHECKSUM=false` (wiki ghi nhận lỗi báo nhầm trên server Linux). |
| Bị kick do anti-cheat khi dùng mod | Đổi `AntiCheatXP`, `AntiCheatSpeed`, `AntiCheatHit`... trong `.ini` sang mức Log |
| "Version mismatch" | `docker compose restart pz` để server cập nhật bằng client |
| Lag / tràn RAM | Tăng `SERVER_MEMORY` (và `CONTAINER_MEMORY_LIMIT` theo), giảm số mod |
| Server không phản hồi dù đã start | Thử đặt `BIND_IP` bằng IP của container |

## Cấu trúc

```
compose.yaml          # service pz (server) + backup
.env.example          # toàn bộ cấu hình → copy thành .env
config/mods.txt       # danh sách mod
docker/Dockerfile     # Debian + SteamCMD + rcon-cli
docker/entrypoint.sh  # cài/cập nhật, ghi .ini, tắt an toàn
docker/backup.sh      # backup định kỳ + xoay vòng
backups/              # file backup .tar.gz (tạo tự động)
```
