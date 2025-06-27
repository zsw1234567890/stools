简体中文 | [English](README.md)

# stools - Linux 工具箱

`stools` 是一个轻量级的 Linux 命令行工具箱框架，旨在帮助用户方便地管理和使用各种自定义脚本工具。

工具箱收集了一些常用工具，例如：
-   **`lan_ping_scan`**: 扫描局域网中存活的主机。
-   **`port_scan`**: 对指定IP执行端口扫描。
-   **`smart_capture`**: 智能抓包并可选使用AI进行分析。
-   **`remote_exec`**: 批量远程执行命令或传输文件 (依赖 `expect` 和 `hostsinfo` 文件)。
-   **`setup_ssh_trust`**: 批量设置SSH免密登录 (本机到远程, 依赖 `expect` 和 `hostsinfo` 文件)。
-   **`ssh_quick_trust`**: 为单个远程主机快速设置SSH免密登录 (通过参数指定主机和凭证)。
-   **`ai`**: 通用AI助手，通过命令行或管道接收提示词并调用OpenAI API获取回答 (依赖 `OPENAI_API_KEY` 环境变量)。

后期会不断添加和更新工具，欢迎大家参与共创。

## 特性

-   **统一入口**：通过 `stl` 命令集中管理和调用所有工具。
-   **源管理**：支持从不同的源（例如 GitHub 或私有服务器）获取工具列表和脚本。
-   **工具管理**：
    -   列出可用工具。
    -   搜索工具（按名称、描述、标签）。
    -   下载所有工具到本地，方便离线使用。
    -   更新单个或所有已安装的工具。
    -   卸载单个工具。
-   **易于扩展**：只需将新的 shell 脚本添加到工具源的 `tools` 目录，并在 `meta/tools.json` 中注册即可。
-   **环境友好**：安装脚本会自动检查并尝试安装所需依赖 (`curl`, `jq`)。

## 安装

您可以使用以下命令一键安装 `stools`：

```bash
wget -O - https://raw.githubusercontent.com/frogchou/stools/main/install.sh | bash
```
或者，如果您的仓库地址不同，请替换上面的 URL。

### 一个可用的国内源

您也可以使用以下命令一键安装 `stools`，并指定国内源：
```bash
wget -O - http://d.frogchou.com/linux/stl.sh | bash
```

安装脚本将会：
1.  检查并安装依赖项 (`curl`, `jq`)。
2.  检查并处理潜在的命令或目录冲突。
3.  将 `stools` 安装到 `/opt/stools`。
4.  在 `/usr/local/bin` 创建 `stl` 命令的软链接。
5.  在用户主目录下创建配置文件 `~/.stoolsrc`。

## 卸载

要卸载 `stools`，请执行项目中的 `uninstall.sh` 脚本（需要 root 或 sudo 权限）：

```bash
# 假设您已克隆仓库或拥有 uninstall.sh 文件
sudo bash uninstall.sh
```
或者，你可以尝试使用以下命令：
```bash
wget -qO- https://raw.githubusercontent.com/frogchou/stools/main/uninstall.sh | bash
```

## 使用方法

安装完成后，您可以使用 `stl` 命令。

### 基本命令

-   `stl help` 或 `stl -h`, `stl --help`: 显示帮助信息。
-   `stl list`: 列出所有可用的工具及其描述。
-   `stl search <关键词>`: 根据关键词（不区分大小写）搜索工具的名称、描述或标签。
-   `stl <工具名> [参数...]`: 执行指定的工具。如果工具未在本地，`stl` 会尝试从配置的源下载它。

### 工具管理命令

-   `stl install-all`: 从源下载所有可用工具到本地 (`/opt/stools/tools`)，方便离线使用。
-   `stl update <工具名>`: 从源重新下载并更新指定的工具。
-   `stl update-all`: 从源重新下载并更新所有在元数据中列出的工具。
-   `stl uninstall <工具名>`: 从本地卸载指定的工具（会请求确认）。

### 源管理命令

-   `stl source <URL>`: 设置新的工具源地址。工具列表 (`meta/tools.json`) 和工具脚本将从这个新的 URL 获取。
    例如：`stl source https://your-mirror.com/stools`

#### 推荐的国内源

-   **frogchou国内源**: `http://d.frogchou.com/linux/stools/`

## 配置文件

`stools` 的配置文件位于 `~/.stoolsrc`。它主要用于存储工具源的 URL。

-   `SOURCE`: 工具源的 URL。

此外，某些工具（如 `smart_capture` 的 AI 分析功能）可能依赖于环境变量进行配置。

### 环境变量

-   **`OPENAI_API_KEY`**:
    -   **用途**: 用于 `smart_capture` 工具调用 OpenAI API 进行 pcap 文件分析。
    -   **设置方法**: 您需要在您的 shell 环境中设置此环境变量。例如，在 `.bashrc` 、 `.zshrc` 或者 `~/.stoolsrc` 文件中添加：
        ```bash
        export OPENAI_API_KEY="sk-YourOpenAIapiKeyGoesHere"
        ```

## 如何添加新工具

1.  **创建工具脚本**：编写您的 shell 脚本 (例如 `my_new_tool.sh`) 并将其放置在您的工具源仓库的 `tools/` 目录下。
2.  **更新元数据**：编辑工具源仓库中的 `meta/tools.json` 文件，添加一个描述您的新工具的 JSON 对象。格式如下：
    ```json
    [
      {
        "name": "lan_ping_scan",
        "description": "扫描局域网中存活的主机",
        "file": "lan_ping_scan.sh",
        "tags": ["ping", "network", "scan"]
      },
      {
        "name": "my_new_tool",
        "description": "这是我的新工具的描述",
        "file": "my_new_tool.sh",
        "tags": ["new", "custom", "example"]
      }
    ]
    ```
    -   `name`: 工具的调用名称 (不含 `.sh` 后缀)。
    -   `description`: 工具的简短描述。
    -   `file`: 工具脚本的文件名 (在 `tools/` 目录下)。
    -   `tags`: 一个包含相关关键词的数组，用于搜索。

3.  用户在下次执行 `stl list`, `stl search`, `stl install-all`, `stl update-all` 或尝试运行新工具时，`stools` 会从更新后的源获取最新的元数据。

## 贡献

欢迎提交问题、功能请求或拉取请求！

## 许可证

本项目根据 [MIT 许可证](LICENSE) 的条款进行许可。