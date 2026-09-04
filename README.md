# D2 Dedicated Server - Release 发布目录

本目录用于存放所有开发完成的暗黑破坏神 II 1.14d 服务端特色功能插件（Feature DLLs）的发布产物、源码与技术文档。

---

## 已发布的特色功能插件列表

| 插件名称 | 插件目录 | 产物文件 | 功能简要说明 |
| :--- | :--- | :--- | :--- |
| **Rune Exchange** | [rune_exchange/](rune_exchange/) | `bin/rune_exchange.dll` | 出售暗金装备置换高级符文（18#~33#），防刷不可回购，商店货架即时刷新，系统广播提示，全动态 INI 热重载 |

---

## 插件通用部署说明

1. **宿主机与容器挂载对应关系**：
   - 宿主机目录：`/home/cfwd2/d2mods/`
   - K3s 游戏服务端容器内路径：`/mods/`
   - 驱动器映射（Wine 环境）：`Z:\mods\`

2. **快速部署命令**：
   ```bash
   # 将目标插件的 bin 目录下 .dll 和 .ini 拷贝至服务器 /home/cfwd2/d2mods/
   # 并执行优雅滚动重启：
   sudo k3s kubectl rollout restart deployment/d2gs-1-14d -n realm
   ```

3. **自动化部署脚本**：
   项目配套的 `temp/deploy_mod.py` 脚本支持一键 SFTP 上传与滚动重启。

---

详细技术原理、INI 配置与编译说明，请查阅各个插件目录下的独立 `README.md`。
