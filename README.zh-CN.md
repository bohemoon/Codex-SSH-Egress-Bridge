# Codex SSH 出口桥接

这个项目用于让远程 Linux 主机上的 Codex，通过 SSH 客户端所在机器的网络访问
HTTPS 服务。它由三部分组成：

1. OpenSSH 反向动态端口转发，在远端回环地址创建 SOCKS5 监听；
2. 无第三方依赖的 HTTP→SOCKS5 转换器；
3. 可选的用户级 Codex 启动 wrapper。

整个方案不修改 `/usr`、系统 Node.js 或系统级 Codex 安装。

> [!IMPORTANT]
> 这是社区方案，不是 OpenAI 官方网络功能。只应在组织规定、网络政策和相关条款
> 允许的范围内使用。它不会绕过账户、地区或服务资格限制。

## 推荐：图形界面

Windows 用户可以直接双击仓库根目录的 `launch-gui.cmd`。界面会引导你按顺序完成：

1. 从本机 SSH 配置中选择远端别名并测试连接；
2. 启动或停止反向 SOCKS 隧道；
3. 把必要文件部署到远端并完成用户级安装；
4. 验证网络、执行只读诊断或打开远端 Codex。

界面默认不会覆盖已有的 `codex` 命令。“安装为默认 codex 命令”选项默认不勾选，
只有确认远端没有需要保留的旧 wrapper 时才应启用。SSH 配置和运行日志仅在本机读取，
不会写入仓库或上传。

## 快速开始

Windows SSH 客户端执行：

```powershell
.\scripts\windows\start-reverse-socks.ps1 -SshHost example-remote
```

其中 `example-remote` 是你自己的 SSH 配置别名。不要把真实
`~/.ssh/config` 提交到仓库。

远端 Linux 执行：

```bash
./scripts/linux/install.sh
~/.local/bin/codex-ssh-eg-verify
~/.local/bin/codex-ssh-eg --version
```

默认继续使用独立命令 `codex-ssh-eg`。如果确认要让代理启动器成为默认的
`codex` 命令，需要显式执行：

```bash
./scripts/linux/install.sh --wrap-codex
```

自定义端口时，两端必须一致：

```powershell
.\scripts\windows\start-reverse-socks.ps1 `
  -SshHost example-remote `
  -RemoteSocksPort 11080
```

```bash
SOCKS_PORT=11080 HTTP_PROXY_PORT=18080 ./scripts/linux/install.sh
```

## 超时排查

```bash
~/.local/bin/codex-ssh-eg-diagnose
```

依次确认：SOCKS 握手、HTTP 转换器、HTTPS 探测、所有 app-server 进程的代理
环境变量，以及是否有未继承代理的旧 app-server 占用控制套接字。

诊断脚本是只读的，不会停止进程，也不会读取 Codex 登录令牌。只有在你已经确认
存在“父进程为 1、未带代理变量、命令行匹配”的旧 code-mode host 时，才运行：

```bash
~/.local/bin/codex-ssh-eg-recover-orphan
```

## 信息安全

- 仓库中不包含真实用户名、主机名、IP、绝对家目录、token 或设备验证码。
- 所有监听默认只绑定 `127.0.0.1`。
- 不读取、不复制 `~/.codex/auth.json`。
- 发布前执行 `python scripts/audit_public_tree.py`。
- 日志仍可能包含目标域名和时间戳，公开日志前应人工检查。

完整原理、卸载方式和开发说明见 [英文 README](README.md)。Codex 的安装与登录
以 [Codex CLI 官方文档](https://learn.chatgpt.com/docs/codex/cli) 和
[认证文档](https://learn.chatgpt.com/docs/auth) 为准。
