# esai单词更新发布

更新使用 [Sparkle 2.10.1](https://sparkle-project.org/documentation/)，与 [esai 定时关闭](https://github.com/fitzsmith2000/esai) 的客户端机制一致。Apple Silicon 版本读取 `https://raw.githubusercontent.com/fitzsmith2000/esai-wordbar/main/updates/appcast-arm64.xml`。自动更新默认关闭；开启后每小时检查，自动下载，并在正常退出时安装。手动检查始终可用。旧版 0.7.1 没有更新器，需要手动安装一次新版。

签名是必需的：`Info.plist` 固定 Ed25519 公钥，发布脚本签署 ZIP 与 appcast，并验证 ZIP 与应用公钥一致。私钥只保存在本机 `~/.config/esai-wordbar/updates/ed25519.seed`，不进入源码或安装包。更新应用仍为 ad hoc 代码签名，尚未通过 Apple Developer ID 公证。不要为已经发布的应用重建密钥；丢失密钥时先从备份恢复。

## 每次发布

1. 增加 `Info.plist` 的版本号和构建号，更新 `README.md`。
2. 运行 `zsh package.sh`。它生成不含 Collins 数据库的公开 `.dmg`、`.pkg` 和供 Sparkle 安装的应用专用 `.zip`。若本机有个人词库，还会额外生成含词库的个人安装包，不得上传到公开 Release。旧的个人安装版启动时会将词库复制到用户的应用支持目录，后续更新沿用它。
3. 运行 `python3 Scripts/make-appcast.py build/esai-wordbar-<版本>-apple-silicon.zip --notes '本次更新内容'`。脚本验证 ZIP 元数据，签署 ZIP 和 appcast，并保存近期条目。签名后不要修改 ZIP 或 XML。
4. 把源码和签名后的 `updates/appcast-arm64.xml` 发布到 `fitzsmith2000/esai-wordbar`，创建 `v<版本>` Release，上传与 XML 中 URL 完全一致的 ZIP 和 `-public.dmg`、`-public.pkg`。不要把含 Collins 数据库的个人 DMG/PKG 上传到公开 Release。先确保 Release ZIP 可下载，再让客户端读取新 appcast。
5. 从公开地址下载 XML 与 ZIP，核对大小和 Ed25519 签名，并在真实 Mac 上用上一版的「检查更新…」验证升级。

`Scripts/fetch-sparkle.sh` 下载并校验固定 SHA-256 的官方框架；构建后保留框架原始签名和完整许可文件。`Scripts/create-update-key.swift` 仅在首次制作更新密钥时使用。

`python3 Tests/test-updates.py` 使用隔离的测试应用、临时本地服务器和真实 Sparkle 安装流程验证更新，不使用正式应用的设置或安装位置。
