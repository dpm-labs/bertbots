# BertBots — OpenClaw Fleet on AWS

Terraform project that deploys 2-10 [OpenClaw](https://github.com/openclaw/openclaw) instances on AWS, each running its own Telegram bot. All instances share API keys and a common agent configuration with multi-model support (Anthropic, OpenAI, xAI), skills (Notion, image gen, whisper), and Brave web search.

Each bot runs on a dedicated `t3.small` EC2 instance (~$15/mo) with Docker Compose, CloudWatch logging, and SSM access.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- AWS CLI configured with credentials (`aws configure` or environment variables)
- An AWS account with permissions to create VPC, EC2, IAM, and CloudWatch resources
- One or more Telegram bot tokens (create via [@BotFather](https://t.me/BotFather))
- An Anthropic API key

## Quick Start

```bash
cd terraform

# 1. Create your config from the example
cp terraform.tfvars.example terraform.tfvars

# 2. Edit terraform.tfvars with your real tokens and API key
#    (see Configuration section below)

# 3. Initialize and deploy
terraform init
terraform plan     # review what will be created
terraform apply    # deploy
```

Terraform will output SSH/SSM commands and instance IPs when done.

## Configuration

Edit `terraform/terraform.tfvars` with your values:

```hcl
aws_region = "us-east-1"

instances = {
  "bot-alpha" = {
    telegram_bot_token = "123456:ABC-YOUR-TOKEN"
    telegram_dm_policy = "pairing"
  }
  "bot-beta" = {
    telegram_bot_token = "789012:DEF-YOUR-TOKEN"
    telegram_dm_policy = "allowlist"
    telegram_allow_from = ["12345678"]  # Telegram user IDs
  }
}

secrets = {
  ANTHROPIC_API_KEY    = "sk-ant-..."
  OPENAI_API_KEY       = "sk-..."
  OPENAI_SKILL_API_KEY = "sk-..."
  BRAVE_API_KEY        = "..."
  GOOGLE_API_KEY       = "..."
  NOTION_API_KEY       = "ntn_..."
}

# Agent workspace (optional — clone a shared workspace repo on boot)
workspace_repo       = "https://github.com/your-org/your-workspace"
workspace_repo_path  = "workspace"  # subdirectory within repo (optional)
workspace_repo_token = "ghp_..."    # required for private repos
```

### Instance Options

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `telegram_bot_token` | Yes | — | Bot token from BotFather |
| `telegram_dm_policy` | No | `"pairing"` | `"pairing"`, `"allowlist"`, or `"open"` |
| `telegram_allow_from` | No | `[]` | Telegram user IDs (used with `"allowlist"` policy) |

### Global Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-east-1` | AWS region |
| `secrets` | — | Map of API keys / env vars shared by all instances |
| `default_model` | `anthropic/claude-sonnet-4-6` | Primary model for all bots |
| `instance_type` | `t3.small` | EC2 instance type |
| `root_volume_size` | `30` | Root EBS volume size (GB) |
| `data_volume_size` | `10` | Persistent data volume size per instance (GB) |
| `openclaw_image` | `ghcr.io/openclaw/openclaw:latest` | Docker image |
| `workspace_repo` | `""` | Git repo URL to clone as agent workspace |
| `workspace_repo_path` | `""` | Subdirectory within repo to use as workspace |
| `workspace_repo_token` | `""` | GitHub PAT for private workspace repos |
| `log_retention_days` | `14` | CloudWatch log retention |
| `ssh_public_key` | `""` | SSH public key (enables SSH access) |
| `ssh_allowed_cidrs` | `[]` | CIDRs allowed to SSH in |

### Agent Workspace

You can pre-load each instance with a shared [agent workspace](https://docs.openclaw.ai/concepts/agent-workspace) (AGENTS.md, SOUL.md, tools, etc.) by pointing to a git repo:

```hcl
workspace_repo = "https://github.com/your-org/your-workspace"
```

If the workspace files live in a subdirectory of the repo, specify the path:

```hcl
workspace_repo_path = "workspace"
```

For private repos, create a [classic GitHub PAT](https://github.com/settings/tokens/new) with `repo` scope and add:

```hcl
workspace_repo_token = "ghp_..."
```

On the first boot, the repo is cloned and workspace contents are copied into `~/.openclaw/workspace` inside the container. On subsequent deploys, the clone is skipped to preserve runtime data (memory files, agent state).

### Secrets

API keys are passed as environment variables via Docker Compose's `env_file`. Terraform writes all `secrets` entries plus the per-instance `telegram_bot_token` to a `.env` file on each instance (mode 600). OpenClaw reads them as process environment variables.

Add any keys your agents need to the `secrets` map in `terraform.tfvars`:

```hcl
secrets = {
  ANTHROPIC_API_KEY    = "sk-ant-..."
  OPENAI_API_KEY       = "sk-..."
  OPENAI_SKILL_API_KEY = "sk-..."
  BRAVE_API_KEY        = "..."
  GOOGLE_API_KEY       = "..."
  NOTION_API_KEY       = "ntn_..."
}
```

The `telegram_bot_token` from each instance entry is automatically included as `TELEGRAM_BOT_TOKEN`. You don't need `OPENCLAW_GATEWAY_TOKEN` — these bots use Telegram long-polling with no inbound gateway access.

### Enabling SSH Access

By default, instances are only accessible via SSM Session Manager. To enable SSH:

```hcl
ssh_public_key    = "ssh-ed25519 AAAA..."
ssh_allowed_cidrs = ["1.2.3.4/32"]  # your IP
```

## Common Operations

### Add a bot

1. Create a bot via [@BotFather](https://t.me/BotFather)
2. Add an entry to `instances` in `terraform/terraform.tfvars`
3. `terraform apply`

### Remove a bot

1. Delete the entry from `instances` in `terraform/terraform.tfvars`
2. Remove the data volume from Terraform state first (it has `prevent_destroy`):
   ```bash
   terraform state rm 'aws_ebs_volume.openclaw_data["bot-name"]'
   terraform state rm 'aws_volume_attachment.openclaw_data["bot-name"]'
   ```
3. `terraform apply`
4. Manually delete the orphaned EBS volume in the AWS console (or keep it as a backup)

### Update configuration

Edit `terraform/terraform.tfvars` and run `terraform apply` from `terraform/`. This replaces the affected instances with fresh ones running the new config. Persistent data (workspace memory, agent state) is preserved on a dedicated EBS volume that survives instance replacement.

### Connect to an instance

```bash
# Via SSM (no SSH key needed)
aws ssm start-session --target <instance-id> --region us-east-1

# Via SSH (if configured)
ssh ec2-user@<public-ip>
```

Instance IDs and IPs are shown in Terraform outputs:

```bash
terraform output instance_details
```

### View logs

```bash
# Stream all bot logs
aws logs tail /bertbots/openclaw --follow --region us-east-1

# Filter to one bot
aws logs tail /bertbots/openclaw --follow --log-stream-names bot-alpha
```

### Check health

From inside an instance:

```bash
curl http://127.0.0.1:18789/healthz
docker compose -f /opt/openclaw/compose/docker-compose.yml ps
sudo docker exec openclaw cat /home/node/.openclaw/openclaw.json
```

### View bootstrap logs

If an instance isn't working after deploy:

```bash
# SSM into the instance, then:
cat /var/log/user-data.log
```

## Architecture

```
┌───────────────────────────────────────────────┐
│ VPC 10.0.0.0/16                               │
│  ┌─────────────────────────────────────────┐  │
│  │ Public Subnet 10.0.1.0/24               │  │
│  │                                         │  │
│  │  ┌───────────┐  ┌───────────┐           │  │
│  │  │ bot-alpha │  │ bot-beta  │  ...      │  │
│  │  │ t3.small  │  │ t3.small  │           │  │
│  │  │ Docker    │  │ Docker    │           │  │
│  │  └─────┬─────┘  └─────┬─────┘           │  │
│  └────────┼───────────────┼────────────────┘  │
│           │               │                   │
│           ▼               ▼                   │
│    Internet Gateway (egress only)             │
└───────────────────────────────────────────────┘
            │               │
            ▼               ▼
      Telegram API    Anthropic API
            │
            ▼
      CloudWatch Logs
```

- No inbound ports (Telegram uses long-polling)
- SSH ingress only if explicitly configured
- Each instance has an IAM role for CloudWatch Logs and SSM
- EBS root volumes are encrypted with gp3
- Persistent EBS data volume per instance (`prevent_destroy`) for workspace/memory data
- IMDSv2 required on all instances

### Data Persistence

Each bot instance has a dedicated EBS data volume mounted at `/opt/openclaw/config` (which maps to `~/.openclaw` in the container). This volume persists across instance replacements:

- **Config** (`openclaw.json`, Docker Compose, `.env`) is always overwritten on boot to reflect the latest Terraform state
- **Workspace** is only cloned on first boot — subsequent deploys skip the clone, preserving memory files and agent state
- **Volumes have `prevent_destroy`** — Terraform will refuse to delete them. See "Remove a bot" above for the cleanup workflow

On Nitro instances (t3.small), the boot script discovers the volume via NVMe serial number matching and formats it with ext4 on first boot.

### Security Note

Secrets (API keys, bot tokens, GitHub PAT) are passed via EC2 user data, which means they are stored in plaintext in the instance metadata and visible to anyone with `ec2:DescribeInstanceAttribute` IAM access in your AWS account. This is fine for personal use but not recommended for production. A more robust approach would use AWS Secrets Manager or SSM Parameter Store and have the instance pull secrets at boot.

The workspace repo token also persists in `/var/log/user-data.log` after use. If this concerns you, SSM into the instance and clear the log after bootstrap.

## Costs

| Resource | Estimate |
|----------|----------|
| EC2 t3.small per instance | ~$15/mo |
| EBS gp3 30GB root per instance | ~$2.40/mo |
| EBS gp3 10GB data per instance | ~$0.80/mo |
| CloudWatch Logs | ~$0.50/GB ingested |
| Data transfer (outbound) | ~$0.09/GB after 1GB free |

No load balancer, NAT gateway, or other expensive resources.

## Cleanup

```bash
cd terraform/

# Data volumes have prevent_destroy — remove them from state first
terraform state list | grep aws_ebs_volume.openclaw_data | xargs -I{} terraform state rm '{}'
terraform state list | grep aws_volume_attachment.openclaw_data | xargs -I{} terraform state rm '{}'

# Destroy remaining resources
terraform destroy
```

After destroy, manually delete the orphaned EBS data volumes in the AWS console if you no longer need them.
