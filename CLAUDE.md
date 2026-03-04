# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BertBots deploys 1-10 OpenClaw bot instances on AWS via Terraform. Each instance runs a Telegram bot in Docker on a dedicated EC2 instance. All instances share API keys and agent configuration. Telegram uses long-polling (outbound only — no inbound ports).

## Terraform Commands

```bash
cd terraform/
terraform init          # first time or after provider changes
terraform plan          # preview changes
terraform apply         # deploy (replaces instances on config change)
terraform destroy       # tear down all resources
terraform output instance_details  # show IPs, SSM commands
```

All Terraform commands must be run from the `terraform/` directory.

## Architecture

- **`terraform/`** — all infrastructure code lives here
- **`terraform/templates/`** — three templates rendered by Terraform into EC2 user_data:
  - `openclaw_config.json5.tftpl` — OpenClaw agent config (models, skills, channels, hooks)
  - `docker-compose.yml.tftpl` — container definition with CloudWatch logging
  - `user_data.sh.tftpl` — bootstrap script (install Docker, write config, clone workspace, start container)
- **`terraform/ec2.tf`** — uses `for_each` over `var.instances` map; nested `templatefile()` calls render config into user_data
- **`terraform.tfvars`** — not committed (contains secrets); see `terraform.tfvars.example`

## Key Patterns

**Instance lifecycle**: Any change to user_data triggers instance replacement (`user_data_replace_on_change = true`). This means config changes destroy and recreate instances — workspace memory is lost.

**Terraform template escaping**: The OpenClaw config uses `${VAR_NAME}` for env var interpolation at runtime. In the `.tftpl` template, these must be escaped as `$${VAR_NAME}` so Terraform outputs the literal `${VAR_NAME}`.

**Config file naming**: The config is written as `openclaw.json` (not `.json5`). OpenClaw's doctor creates its own `openclaw.json` on first boot — writing to this path prevents a precedence conflict where doctor's copy overrides ours.

**Workspace mount**: `/opt/openclaw/config` on the host maps to `/home/node/.openclaw` in the container. Workspace files go into `/opt/openclaw/config/workspace/` so they appear at `~/.openclaw/workspace/` inside the container.

**Secrets flow**: API keys are in `terraform.tfvars` → rendered into `/opt/openclaw/compose/.env` → loaded by Docker Compose `env_file` → available as process env vars in the container. The OpenClaw config references them via `${VAR_NAME}` syntax or SecretRefs (only for `botToken`).

## Operational Commands (on instance via SSM)

```bash
# Connect
aws ssm start-session --target <instance-id> --region <region>

# Container status and logs
sudo docker compose -f /opt/openclaw/compose/docker-compose.yml ps
sudo docker compose -f /opt/openclaw/compose/docker-compose.yml logs -f

# View running config
sudo docker exec openclaw cat /home/node/.openclaw/openclaw.json

# Check workspace
sudo docker exec openclaw ls /home/node/.openclaw/workspace/

# Check env vars
sudo docker exec openclaw env | grep API_KEY

# Bootstrap log (if container won't start)
cat /var/log/user-data.log

# CloudWatch logs (from local machine)
aws logs tail /bertbots/openclaw --follow --region <region>
```

## Adding/Removing Bots

Edit `instances` map in `terraform.tfvars` and `terraform apply`. Each map key becomes an EC2 instance. The `telegram_bot_token` is per-instance; everything else (API keys, model config, workspace) is shared.

## Git Conventions

- Semantic commit prefixes: `feat:`, `fix:`, `docs:`
- Do not add co-author lines to commits
- `terraform.tfvars` is gitignored (contains secrets)
