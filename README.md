# agentic-ai-linux-troubleshooting

A small Bash-based Linux/DevOps troubleshooting assistant that uses an LLM (via Ollama) to request approved read-only diagnostic commands and explain their output.

## Purpose

This repository contains `agentic-ai-linux-troubleshooter.sh`, a script that lets an LLM suggest READ-ONLY diagnostic Linux commands. The script validates commands against a local allow-list before executing them and returns the output to the assistant for explanation.

## Requirements

- `bash`
- `curl`
- `jq`

## Environment

Export your Ollama API key and (optionally) the model to use:

```bash
export OLLAMA_API_KEY="your-api-key"
export OLLAMA_MODEL="gpt-oss:120b"
```

## Usage

Run the script interactively:

```bash
./agentic-ai-linux-troubleshooter.sh
```

Ask questions like:
- "Why is my server running out of disk?"
- "Check memory usage"
- "Is SSH running?"
- "Show me the top CPU consuming processes"

Type `exit` to quit. Type `clear` to reset the conversation.

## Allowed (Read-only) Diagnostic Commands

The script validates commands against an internal allow-list. Examples of approved commands include:

- `uptime`
- `uname -a`
- `df -h`
- `free -h`
- `ps aux --sort=-%cpu | head -20`
- `ps aux --sort=-%mem | head -20`
- `ss -tulpn`
- `du -sh /*`, `du -sh /var/*`, `du -sh /tmp/*`
- `systemctl status <service>` (validated safe pattern)
- `journalctl -u <service> -n 50 --no-pager` (validated safe pattern)

The script explicitly blocks destructive operations (for example: `rm`, `mv`, `chmod`, `chown`, `kill`, `reboot`, `shutdown`, `systemctl restart`, etc.).

## Security Notes

- This tool intentionally executes only read-only diagnostic commands.
- Never expose your API key to untrusted networks or public repositories.

## Files

- `agentic-ai-linux-troubleshooter.sh` — main interactive script.

## Author

Author: Charanjit Cheema

Email: charanjit.cheema@cjcheema.com

---
Small, focused utility for safe, explainable Linux diagnostics driven by an LLM.
