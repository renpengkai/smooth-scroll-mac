# SmoothScroll

一个极小的 macOS 菜单栏工具，让外接鼠标的滚轮像触控板一样顺滑。

平滑算法移植自 [Mos](https://github.com/Caldis/Mos) 的 `ScrollCore`（事件拦截、轴归一化、峰值滤波、指数插值、`CVDisplayLink` 逐帧派发、触控板 phase 模拟），默认参数与 Mos 一致，因此手感与 Mos 的「平滑滚动」相同。Mos 的其余功能（按键绑定、Logi HID++、按应用配置、偏好窗口、自动更新等）全部去掉，以换取体积。

- 仅支持 Apple Silicon，macOS 13+
- 零第三方依赖，没有资源文件，界面只有一个菜单栏菜单
- 本地不需要 Xcode：由 GitHub Actions 的 macOS runner 编译打包

## 功能

| 菜单项 | 说明 |
| --- | --- |
| 平滑滚动 | 总开关 |
| 反转鼠标滚动方向 | 默认开启（与 Mos 一致）：系统「自然滚动」开着时，鼠标滚轮恢复传统方向，触控板不受影响 |
| 模拟触控板 | 给合成事件附带触控板 phase，部分应用会出现回弹等触控板效果 |
| 最小步长 / 速度增益 / 惯性时长 | 对应 Mos 的 step / speed / duration，默认 33.6 / 2.70 / 4.35 |
| 登录时启动 | 需要先把 App 放进「应用程序」文件夹 |

固定热键（与 Mos 默认值相同，只认左侧修饰键）：

- 按住 **左 Option**：5 倍速滚动
- 按住 **左 Shift**：纵向滚动转为横向
- 按住 **左 Command**：临时关闭平滑（`Cmd + 滚轮` 缩放不受影响）

点击鼠标左键会立即停住惯性。触控板、Magic Mouse、远程桌面已平滑过的事件原样放行。

## 用 Homebrew 安装（推荐）

```bash
brew install --cask renpengkai/tap/smoothscroll
```

Cask 放在 [renpengkai/homebrew-tap](https://github.com/renpengkai/homebrew-tap)，安装时会自动去掉隔离属性，装完直接打开就行，然后按下面第 3 步授权。升级与卸载：

```bash
brew upgrade --cask smoothscroll      # 升级后需要重新授权, 见下文
brew uninstall --cask smoothscroll    # 加 --zap 同时删除设置
```

## 手动获取安装包

- 正式版本：[Releases](https://github.com/renpengkai/smooth-scroll-mac/releases) 下载 `SmoothScroll-<版本>.zip`。
- 开发构建：每次推送 `main`，Actions 的 `build-macos` 都会构建，在该次运行页面底部的 **Artifacts** 下载。

## 安装与授权

1. 把 `SmoothScroll.app` 拖进「应用程序」（Homebrew 安装可跳过第 1、2 步）。
2. 包只做了 ad-hoc 签名、未公证，首次打开会被 Gatekeeper 拦截。可以右键 App 选择「打开」，或在终端执行：

   ```bash
   xattr -dr com.apple.quarantine /Applications/SmoothScroll.app
   ```

3. 启动后会弹出辅助功能授权提示：打开「系统设置 → 隐私与安全性 → 辅助功能」，勾选 SmoothScroll。勾选后约 1 秒内自动生效，不用重启 App。

**每次更新到新构建都要重新授权。** ad-hoc 签名的身份就是二进制哈希，新构建在系统看来是另一个 App，旧的授权条目会失效。做法：在辅助功能列表里选中 SmoothScroll，点「−」删除，再重新打开 App 授权。

如果同时装了 Mos，请先退出 Mos，否则两边会叠加平滑。

## 与 Mos 对照验收

两边用默认参数，在 Safari 长网页和 Finder 长列表里分别试：

- [ ] 触控板滚动与系统原生一致，没有被二次平滑
- [ ] 鼠标滚一格：一段连续的减速滚动，起步不突跳、结束没有台阶感
- [ ] 连续快速滚动：速度叠加，松手后惯性衰减与 Mos 一致
- [ ] 滚动中反向拨滚轮：立即转向，不会先把旧惯性滚完
- [ ] 惯性中点击左键：立即停住
- [ ] 按住左 Command 滚动：Safari/预览里的缩放正常
- [ ] 菜单关闭「平滑滚动」后恢复系统原生逐格滚动
- [ ] 外接高刷显示器上不卡顿（插拔显示器、休眠唤醒后仍然顺滑）

## 发布新版本

```bash
git tag v0.2.0 && git push origin v0.2.0
```

`build-macos` 会构建并发布 Release。tap 仓库每 6 小时自动把 Cask 同步到最新 Release；想立即同步可以手动触发：

```bash
gh workflow run update-smoothscroll.yml -R renpengkai/homebrew-tap
```

## 本地构建（可选）

有 Xcode 或完整 Command Line Tools 的 Mac 上：

```bash
./scripts/package-app.sh          # 产物在 dist/
```

## 目录

```
Sources/SmoothScroll/
  ScrollCore/   移植自 Mos 的滚动热路径
  App/          菜单栏界面、设置、授权流程
Packaging/Info.plist
scripts/package-app.sh
.github/workflows/build-macos.yml
```

## 许可证

`Sources/SmoothScroll/ScrollCore/` 改编自 Caldis 的 Mos，Mos 以 [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/) 授权。本项目整体同样以 CC BY-NC 4.0 发布：可以自由使用和修改，但必须署名，**不得用于商业用途**。详见 [LICENSE](LICENSE) 与 [NOTICE](NOTICE)。
