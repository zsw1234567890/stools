[简体中文](README_zh-CN.md) | English

# stools - Linux Toolbox

`stools` is a lightweight Linux command-line toolbox framework designed to help users conveniently manage and use various custom script tools.

The toolbox collects some commonly used tools, for example:
-   **`lan_ping_scan`**: Scans for active hosts in the local area network.
-   **`port_scan`**: Performs a port scan on a specified IP address.
-   **`smart_capture`**: Intelligently captures network packets and optionally analyzes them using AI.
-   **`remote_exec`**: Executes commands or transfers files批量 remotely on multiple hosts (relies on `expect` and the `hostsinfo` file).
-   **`setup_ssh_trust`**: Sets up SSH passwordless login批量 from the local machine to remote hosts (relies on `expect` and the `hostsinfo` file).
-   **`ssh_quick_trust`**: Quickly sets up SSH passwordless login for a single remote host (specifying host and credentials via parameters).
-   **`ai`**: A general-purpose AI assistant that receives prompts via command line or pipe and calls the OpenAI API to get answers (relies on the `OPENAI_API_KEY` environment variable).

More tools will be added and updated in the future. Contributions are welcome!

## Features

-   **Unified Entry Point**: Centrally manage and invoke all tools via the `stl` command.
-   **Source Management**: Supports fetching tool lists and scripts from different sources (e.g., GitHub or private servers).
-   **Tool Management**:
    -   List available tools.
    -   Search for tools (by name, description, tags).
    -   Download all tools locally for offline use.
    -   Update a single or all installed tools.
    -   Uninstall a single tool.
-   **Easy to Extend**: Simply add new shell scripts to the `tools/` directory of your tool source and register them in `meta/tools.json`.
-   **Environment-Friendly**: The installation script automatically checks and attempts to install required dependencies (`curl`, `jq`).

## Installation

You can install `stools` with a single command:

```bash
wget -O - https://raw.githubusercontent.com/frogchou/stools/main/install.sh | bash
```
Alternatively, if your repository address is different, replace the URL above.

The installation script will:
1.  Check and install dependencies (`curl`, `jq`).
2.  Check and handle potential command or directory conflicts.
3.  Install `stools` to `/opt/stools`.
4.  Create a symbolic link for the `stl` command in `/usr/local/bin`.
5.  Create a configuration file `~/.stoolsrc` in the user's home directory.

## Uninstallation

To uninstall `stools`, execute the `uninstall.sh` script from the project (requires root or sudo privileges):

```bash
# Assuming you have cloned the repository or have the uninstall.sh file
sudo bash uninstall.sh
```
Alternatively, you can try using the following command:
```
wget -qO- https://raw.githubusercontent.com/frogchou/stools/main/uninstall.sh | bash
```

## Usage

After installation, you can use the `stl` command.

### Basic Commands

-   `stl help` or `stl -h`, `stl --help`: Display help information.
-   `stl list`: List all available tools and their descriptions.
-   `stl search <keyword>`: Search for tools by name, description, or tags (case-insensitive).
-   `stl <tool_name> [parameters...]`: Execute the specified tool. If the tool is not available locally, `stl` will attempt to download it from the configured source.

### Tool Management Commands

-   `stl install-all`: Download all available tools from the source to the local machine (`/opt/stools/tools`) for offline use.
-   `stl update <tool_name>`: Re-download and update the specified tool from the source.
-   `stl update-all`: Re-download and update all tools listed in the metadata from the source.
-   `stl uninstall <tool_name>`: Uninstall the specified tool from the local machine (will ask for confirmation).

### Source Management Commands

-   `stl source <URL>`: Set a new tool source URL. The tool list (`meta/tools.json`) and tool scripts will be fetched from this new URL.
    Example: `stl source https://your-mirror.com/stools`

#### Recommended Mirror for Mainland China

-   **frogchou's China Mirror**: `http://d.frogchou.com/linux/stools/`

## Configuration File

The configuration file for `stools` is located at `~/.stoolsrc`. It is primarily used to store the tool source URL.

-   `SOURCE`: The URL of the tool source.

Additionally, some tools (like the AI analysis feature in `smart_capture`) may rely on environment variables for configuration.

### Environment Variables

-   **`OPENAI_API_KEY`**:
    -   **Purpose**: Used by the `smart_capture` and `ai` tools to call the OpenAI API.
    -   **Setup**: You need to set this environment variable in your shell environment. For example, add the following to your `.bashrc`, `.zshrc`, or even `~/.stoolsrc` file:
        ```bash
        export OPENAI_API_KEY="sk-YourOpenAIapiKeyGoesHere"
        ```
    -   **Note**: Please replace `"sk-YourOpenAIapiKeyGoesHere"` with your actual OpenAI API key. This key is not stored in the `~/.stoolsrc` file but is read directly from the environment variables when the script is executed.

## How to Add New Tools

1.  **Create Tool Script**: Write your shell script (e.g., `my_new_tool.sh`) and place it in the `tools/` directory of your tool source repository.
2.  **Update Metadata**: Edit the `meta/tools.json` file in your tool source repository and add a JSON object describing your new tool. The format is as follows:
    ```json
    [
      {
        "name": "lan_ping_scan",
        "description": "Scans for active hosts in the local area network.",
        "file": "lan_ping_scan.sh",
        "tags": ["ping", "network", "scan"]
      },
      {
        "name": "my_new_tool",
        "description": "This is the description of my new tool.",
        "file": "my_new_tool.sh",
        "tags": ["new", "custom", "example"]
      }
    ]
    ```
    -   `name`: The invocation name of the tool (without the `.sh` suffix).
    -   `description`: A short description of the tool.
    -   `file`: The filename of the tool script (in the `tools/` directory).
    -   `tags`: An array of relevant keywords for searching.

3.  When users next execute `stl list`, `stl search`, `stl install-all`, `stl update-all`, or try to run the new tool, `stools` will fetch the latest metadata from the updated source.

## Contributing

Issues, feature requests, and pull requests are welcome!

## License

This project is licensed under the terms of the [MIT License](LICENSE).