variable "REGISTRY" { default = "ghcr.io/reyemtech" }
variable "VERSION"  { default = "latest" }

group "default" {
  targets = ["upgrade-agent"]
}

target "upgrade-agent" {
  name = "${item.stack}-upgrade-agent-${item.agent}"
  matrix = {
    item = [
      { stack = "laravel", agent = "claude" },
      { stack = "laravel", agent = "codex" },
    ]
  }
  context    = "stacks/${item.stack}"
  dockerfile = "Dockerfile.${item.agent}"
  contexts = {
    base = "target:base-${item.stack}"
  }
  tags = [
    "${REGISTRY}/${item.stack}-upgrade-agent-${item.agent}:${VERSION}",
    "${REGISTRY}/${item.stack}-upgrade-agent-${item.agent}:latest",
  ]
  platforms = ["linux/amd64", "linux/arm64"]
}

target "base-laravel" {
  context    = "stacks/laravel"
  dockerfile = "Dockerfile.base"
  tags       = []  # Not pushed — used as build dependency only
}
