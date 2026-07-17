# 设计

[English](DESIGN.md) | 中文

Remote Work Sessions 有意保持小而清晰。

## 模型

```text
local terminal
  -> rws device
    -> ssh
      -> remote host
        -> remote runtime
        -> shpool session
          -> shell / coding agent / command
```

`rws` 不创建新的传输层。它把 SSH 和 shpool 组合成更短的日常工作流。

设备是可复用的 SSH 目标和 setup 状态。会话是该设备上的 shpool 会话。远端运行环境是 setup 管理的远端账号状态，例如 `shpool`、shpool config 和可选紧凑提示符 block。创建另一个会话时，不应该要求用户再次输入 host。

## 实体

- SSH key：本地身份材料，可以通过 `rws key` 命令创建、查看、重新生成或删除。远端 `authorized_keys` 安装由 setup 处理。
- 设备：可复用本地配置，包含 host、identity 文件、SSH 选项、shpool 路径和提示符偏好。cwd 和默认会话可作为兼容或明确默认值保存，但新的 setup 不要求它们。
- 会话：所选设备上的命名 shpool 会话，可以 attach、detach、kill 和 list。
  Session 可以带本地可选的 agent、cwd 和权限模式元数据，用于 shpool 进程
  状态丢失后重新进入 agent 的最新原生对话；这不是另一个实体。
- 远端运行环境：setup 准备的远端账号状态，包括 shpool 安装、shpool prompt config 和 shell prompt rc blocks。

`default.conf` 中的默认设备指针是关系状态，不是单独实体。工作目录是会话属性，也保留可选设备默认值以兼容旧配置；`rws` 不引入 project 或 workspace 实体。

## 职责

`rws` 负责：

- 设备选择；
- 交互式和非交互式 setup；
- 在用户配置目录下初始化设备；
- 本地 OpenSSH client 依赖检查，并在可能时安装；
- 初始化时创建 SSH key 或显式复用；
- 通过交互式 SSH/password 登录或已授权 bootstrap key 安装公钥；
- 检查远端 shpool 依赖，并在可能时安装固定版本；
- 为支持的远端 shell 设置紧凑提示符；
- 通过重新连接并检查 SSH 与 shpool 完成最终 setup 验证；
- 设备验证后可选创建初始 session，后台创建，不自动 attach；
- 删除设备；
- 构造 SSH 命令；
- shpool attach、force attach、background attach、detach、kill 和 list；
- 默认以全权限前台启动 Codex、Claude Code 或 Kiro CLI，并在 shpool 状态丢失时按保存的 cwd 和权限模式恢复最近对话；
- 基础远端状态检查；
- 创建 session 时创建远端工作目录；
- 在明确选择或配置的目录中执行一次性远端命令。

`rws` 不负责：

- secrets；
- 密码存储；
- 读取或保存交互式密码；
- 公网暴露；
- 文件同步；
- 编辑器集成；
- 终端 panes 或 layouts。
- 复制、解析或备份 coding agent 的对话数据库；
- 恢复断电前未刷盘的进程内状态或未保存文件。

## 为什么使用 shpool

很多远端工作流需要会话持久化，但不需要完整终端复用器。shpool 能让 shell 会话持续存在，同时把窗口、pane 和布局问题留在范围外。

shpool 解决网络断连，不保证主机重启后的进程恢复。带可选 agent 元数据的
Session 提供第二层持久化：本机只记 agent/cwd/access mode，远端 agent 自己
持久化 conversation。重启后 `rws` 以前台方式原子创建新 shpool session，
并以同一个显式选择的权限模式调用 provider 的 cwd-scoped latest-resume 命令。
它不尝试序列化终端进程。

## 兼容性

CLI 是偏 POSIX 风格的 Bash 脚本，目标客户端是 macOS 和 Linux。它要求本地有标准 SSH client，远端主机上有 shpool。
