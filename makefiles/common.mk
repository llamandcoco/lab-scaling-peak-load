.PHONY: help validate build check-image get-alb-dns check-health-ec2 check-health-ecs

# Configuration
AWS_REGION := ca-central-1
ECR_REPO_NAME := lab-scaling-peak-load-registry
ALB_NAME      := lab-scaling-peak-load-alb
DASHBOARD_NAME := lab-scaling-peak-load
K6_PROMETHEUS_RW_SERVER_URL ?= http://localhost:9090/api/v1/write
K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM ?= false
K6_OUTPUT ?= experimental-prometheus-rw
PROJECT_ROOT ?= $(CURDIR)
CI_CD_DIR := $(PROJECT_ROOT)/aws/00-ci-cd
SHARED_INFRA_DIR := $(PROJECT_ROOT)/aws/00-shared-infra
ASG_DIR := $(PROJECT_ROOT)/aws/10-ec2-asg
EC2_TG_DIR := $(PROJECT_ROOT)/aws/10-ec2-asg/05-alb-tg
ECS_DIR := $(PROJECT_ROOT)/aws/11-ecs-fargate
APPS_DIR := $(PROJECT_ROOT)/apps
ENV_FILE := $(PROJECT_ROOT)/.env
ENV_EXAMPLE := $(PROJECT_ROOT)/.env.example
TG_ARGS ?=
TG_PLAN_ARGS := $(TG_ARGS)
TG_APPLY_ARGS := -auto-approve $(TG_ARGS)
TG_DESTROY_ARGS := -auto-approve $(TG_ARGS)

# Load .env if it exists, otherwise show setup instructions
ifeq ($(wildcard $(ENV_FILE)),)
$(info ⚠️  .env file not found. Copy from .env.example and fill in your values:)
$(info    cp .env.example .env)
$(info    # Edit .env with your GitHub token)
else
include $(ENV_FILE)
export $(shell sed 's/=.*//' $(ENV_FILE))
endif

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
NC := \033[0m # No Color

##@ General

help: ## Display this help
	@echo "$(BLUE)Lab Scaling Peak Load - Makefile Commands$(NC)"
	@echo ""
	@echo "$(YELLOW)Tip: pass extra Terragrunt args via TG_ARGS$(NC)"
	@echo "  e.g. make deploy-shared-infra TG_ARGS=\"-var-file=envs/lab.tfvars\""
	@echo "       make plan-ecs TG_ARGS=\"-lock=false\""
	@echo "       make destroy-ecs TG_ARGS=\"-refresh=false\""
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "Usage:\n  make $(YELLOW)<target>$(NC)\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(BLUE)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Validation

validate: ## Validate Terraform modules (autoscaling, cloudwatch-alarm, instance-profile)
	@echo "$(BLUE)🔍 Validating Terraform modules...$(NC)"
	@cd ../infra-modules/terraform/autoscaling/tests/basic && \
		terraform init -backend=false && terraform validate && \
		echo "$(GREEN)✓ autoscaling module valid$(NC)" || exit 1
	@cd ../infra-modules/terraform/cloudwatch-alarm/tests/basic && \
		terraform init -backend=false && terraform validate && \
		echo "$(GREEN)✓ cloudwatch-alarm module valid$(NC)" || exit 1
	@cd ../infra-modules/terraform/instance-profile/tests/basic && \
		terraform init -backend=false && terraform validate && \
		echo "$(GREEN)✓ instance-profile module valid$(NC)" || exit 1
	@echo "$(GREEN)✅ All modules validated successfully$(NC)"

##@ Build

build: ## Build and push Docker image to ECR
	@echo "$(BLUE)🐳 Building Docker image...$(NC)"
	@bash $(PROJECT_ROOT)/scripts/build-and-push-image.sh
	@echo "$(GREEN)✅ Docker image built and pushed to ECR$(NC)"

check-image: ## Verify Docker image exists in ECR
	@echo "$(BLUE)🔍 Checking ECR for latest image...$(NC)"
	@aws ecr describe-images \
		--repository-name $(ECR_REPO_NAME) \
		--region $(AWS_REGION) \
		--query 'imageDetails[?imageTags!=`null`]|[0].imageTags' \
		--output text || (echo "$(RED)❌ Image not found. Run 'make build' first$(NC)" && exit 1)
	@echo "$(GREEN)✓ Image found in ECR$(NC)"

get-alb-dns: ## Get ALB DNS name
	@echo "$(BLUE)📍 ALB DNS Name:$(NC)"
	@aws elbv2 describe-load-balancers \
		--names $(ALB_NAME) \
		--region $(AWS_REGION) \
		--query 'LoadBalancers[0].DNSName' \
		--output text 2>/dev/null || echo "$(YELLOW)⚠ ALB not found yet$(NC)"

check-health-ec2: ## Check ALB health endpoint (EC2 ASG)
	@echo "$(BLUE)🏥 Checking ALB health (EC2)...$(NC)"
	@bash -c 'ALB_DNS="$$(aws elbv2 describe-load-balancers --names $(ALB_NAME) --region $(AWS_REGION) --query "LoadBalancers[0].DNSName" --output text 2>/dev/null || true)"; if [ -n "$$ALB_DNS" ]; then \
		echo "Testing: http://$$ALB_DNS/healthz"; if curl -sSf http://$$ALB_DNS/healthz >/dev/null; then \
			printf "$(GREEN)✓ ALB health check passed$(NC)\\n"; else \
			printf "$(YELLOW)⚠ Waiting for instances to become healthy...$(NC)\\n"; fi; \
	else \
		printf "$(RED)❌ ALB not found$(NC)\\n"; \
		printf "$(YELLOW)⚠ Deploy the ALB stack before re-running$(NC)\\n"; fi'

check-health-ecs: ## Check ALB health endpoint (ECS)
	@echo "$(BLUE)🏥 Checking ALB health (ECS)...$(NC)"
	@bash -c 'ALB_DNS="$$(aws elbv2 describe-load-balancers --names $(ALB_NAME) --region $(AWS_REGION) --query "LoadBalancers[0].DNSName" --output text 2>/dev/null || true)"; if [ -n "$$ALB_DNS" ]; then \
		echo "Testing: http://$$ALB_DNS/healthz"; if curl -sSf http://$$ALB_DNS/healthz >/dev/null; then \
			printf "$(GREEN)✓ ECS health check passed$(NC)\\n"; else \
			printf "$(YELLOW)⚠ Waiting for ECS tasks to become healthy...$(NC)\\n"; fi; \
	else \
		printf "$(RED)❌ ALB not found$(NC)\\n"; \
		printf "$(YELLOW)⚠ Deploy the ALB stack before re-running$(NC)\\n"; fi'
