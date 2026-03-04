variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "bertbots"
}

variable "instances" {
  description = "Map of OpenClaw bot instances to deploy"
  type = map(object({
    telegram_bot_token = string
    telegram_dm_policy = optional(string, "pairing")
    telegram_allow_from = optional(list(string), [])
  }))

  validation {
    condition     = length(var.instances) >= 1 && length(var.instances) <= 10
    error_message = "Must define between 1 and 10 instances."
  }

  validation {
    condition = alltrue([
      for k, v in var.instances : contains(["pairing", "allowlist", "open"], v.telegram_dm_policy)
    ])
    error_message = "telegram_dm_policy must be one of: pairing, allowlist, open."
  }
}

variable "anthropic_api_key" {
  description = "Anthropic API key shared by all instances"
  type        = string
  sensitive   = true
}

variable "default_model" {
  description = "Default Anthropic model for all instances"
  type        = string
  default     = "anthropic/claude-sonnet-4-5"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 20
}

variable "ssh_allowed_cidrs" {
  description = "CIDRs allowed to SSH into instances. Empty list disables SSH access."
  type        = list(string)
  default     = []
}

variable "ssh_public_key" {
  description = "SSH public key material. Required if ssh_allowed_cidrs is non-empty."
  type        = string
  default     = ""
}

variable "openclaw_image" {
  description = "OpenClaw Docker image"
  type        = string
  default     = "ghcr.io/openclaw/openclaw:latest"
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
}
