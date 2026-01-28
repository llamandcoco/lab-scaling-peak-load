.PHONY: help validate build deploy test-cpu test-rps test-spike test-all monitor logs destroy clean all

# Configuration
AWS_REGION := ca-central-1
ECR_REPO_NAME := lab-scaling-peak-load-registry
ALB_NAME      := lab-scaling-peak-load-alb
DASHBOARD_NAME := lab-scaling-peak-load
K6_PROMETHEUS_RW_SERVER_URL ?= http://localhost:9090/api/v1/write
K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM ?= false
K6_OUTPUT ?= experimental-prometheus-rw
PROJECT_ROOT := $(shell pwd)
CI_CD_DIR := $(PROJECT_ROOT)/aws/00-ci-cd
SHARED_INFRA_DIR := $(PROJECT_ROOT)/aws/00-shared-infra
ASG_DIR := $(PROJECT_ROOT)/aws/10-ec2-asg
APPS_DIR := $(PROJECT_ROOT)/apps
ENV_FILE := $(PROJECT_ROOT)/.env
ENV_EXAMPLE := $(PROJECT_ROOT)/.env.example

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

##@ Deploy

deploy-all: ## Deploy entire infrastructure (all stacks)
	@echo "$(BLUE)🏗️ Deploying all infrastructure stacks...$(NC)"
	@cd $(ASG_DIR) && terragrunt run-all apply --terragrunt-non-interactive
	@echo "$(GREEN)✅ All stacks deployed$(NC)"
	@$(MAKE) get-alb-dns

deploy-sequential: ## Deploy stacks in order (safer, slower)
	@echo "$(BLUE)🏗️ Deploying infrastructure in sequence...$(NC)"
	@cd $(ASG_DIR)/01-iam && terragrunt apply -auto-approve
	@cd $(SHARED_INFRA_DIR)/01-networking && terragrunt apply -auto-approve
	@cd $(SHARED_INFRA_DIR)/02-alb-sg && terragrunt apply -auto-approve
	@cd $(ASG_DIR)/02-instance-sg && terragrunt apply -auto-approve
	@cd $(SHARED_INFRA_DIR)/03-alb && terragrunt apply -auto-approve
	@cd $(ASG_DIR)/03-asg && terragrunt apply -auto-approve
	@cd $(ASG_DIR)/04-cloudwatch && terragrunt apply -auto-approve
	@cd $(ASG_DIR)/05-eventbridge && terragrunt apply -auto-approve
	@cd $(ASG_DIR)/06-dashboard && terragrunt apply -auto-approve
	@echo "$(GREEN)✅ All stacks deployed sequentially$(NC)"
	@$(MAKE) get-alb-dns
##@ Shared Infrastructure (00-shared-infra)

deploy-all-ec2: deploy-shared-infra deploy-asg ## Deploy everything from scratch (shared-infra + EC2 ASG)
	@echo "$(GREEN)✅ Complete EC2 infrastructure deployed$(NC)"

deploy-shared-infra: ## Deploy all shared infrastructure (networking, ALB SG, ALB)
	@echo "$(BLUE)🏗️ Deploying shared infrastructure...$(NC)"
	@cd $(SHARED_INFRA_DIR)/01-networking && terragrunt apply
	@cd $(SHARED_INFRA_DIR)/02-alb-sg && terragrunt apply
	@cd $(SHARED_INFRA_DIR)/03-alb && terragrunt apply
	@echo "$(GREEN)✅ Shared infrastructure deployed (ready for EC2/ECS/EKS)$(NC)"
	@$(MAKE) get-alb-dns

plan-shared-infra: ## Plan all shared infrastructure
	@echo "$(BLUE)📋 Planning shared infrastructure...$(NC)"
	@cd $(SHARED_INFRA_DIR)/01-networking && terragrunt plan
	@cd $(SHARED_INFRA_DIR)/02-alb-sg && terragrunt plan
	@cd $(SHARED_INFRA_DIR)/03-alb && terragrunt plan

destroy-shared-infra: ## Destroy shared infrastructure (WARNING: affects all platforms)
	@echo "$(RED)🗑️ Destroying shared infrastructure...$(NC)"
	@echo "$(YELLOW)⚠️  This will affect EC2, ECS, and EKS platforms!$(NC)"
	@read -p "Are you sure? Type 'yes' to confirm: " confirm && [ "$$confirm" = "yes" ] || (echo "Aborted" && exit 1)
	@cd $(SHARED_INFRA_DIR)/03-alb && terragrunt destroy -auto-approve || true
	@cd $(SHARED_INFRA_DIR)/02-alb-sg && terragrunt destroy -auto-approve || true
	@cd $(SHARED_INFRA_DIR)/01-networking && terragrunt destroy -auto-approve || true
	@echo "$(GREEN)✅ Shared infrastructure destroyed$(NC)"

##@ ASG EC2 Deployment (10-ec2-asg)

deploy-asg: deploy-iam deploy-instance-sg deploy-asg-only deploy-cloudwatch deploy-eventbridge deploy-dashboard ## Deploy EC2 ASG infrastructure (requires shared-infra)
	@echo "$(GREEN)✅ Full ASG infrastructure deployed$(NC)"
	@echo "$(BLUE)Next steps:$(NC)"
	@echo "  1. Watch ASG: https://console.aws.amazon.com/ec2/v2/home#AutoScalingGroups"
	@echo "  2. Check health: make check-health"
	@echo "  3. Run tests: make test-cpu"

plan-iam: ## Plan IAM stack
	@echo "$(BLUE)📋 Planning IAM stack...$(NC)"
	@cd $(ASG_DIR)/01-iam && terragrunt plan

deploy-iam: ## Deploy IAM instance profile
	@echo "$(BLUE)🏗️ [1/6] Deploying IAM instance profile...$(NC)"
	@cd $(ASG_DIR)/01-iam && terragrunt apply
	@echo "$(GREEN)✅ IAM deployed$(NC)"

plan-networking: ## Plan networking stack (shared infrastructure)
	@echo "$(BLUE)📋 Planning networking stack...$(NC)"
	@cd $(SHARED_INFRA_DIR)/01-networking && terragrunt plan

deploy-networking: ## Deploy VPC and subnets (shared infrastructure)
	@echo "$(BLUE)🏗️ [1/3] Deploying VPC and subnets...$(NC)"
	@cd $(SHARED_INFRA_DIR)/01-networking && terragrunt apply
	@echo "$(GREEN)✅ Networking deployed (shared across EC2/ECS/EKS)$(NC)"

plan-security-groups: ## Plan ALB security group (shared infrastructure)
	@echo "$(BLUE)📋 Planning ALB security group...$(NC)"
	@cd $(SHARED_INFRA_DIR)/02-alb-sg && terragrunt plan

deploy-security-groups: ## Deploy ALB security group (shared infrastructure)
	@echo "$(BLUE)🏗️ [2/3] Deploying ALB security group...$(NC)"
	@cd $(SHARED_INFRA_DIR)/02-alb-sg && terragrunt apply
	@echo "$(GREEN)✅ ALB security group deployed (shared across EC2/ECS)$(NC)"

plan-instance-sg: ## Plan instance security group
	@echo "$(BLUE)📋 Planning instance security group...$(NC)"
	@cd $(ASG_DIR)/02-instance-sg && terragrunt plan

deploy-instance-sg: ## Deploy instance security group
	@echo "$(BLUE)🏗️ [2/6] Deploying instance security group...$(NC)"
	@cd $(ASG_DIR)/02-instance-sg && terragrunt apply
	@echo "$(GREEN)✅ Instance security group deployed$(NC)"

plan-secrets: ## Plan secrets stack
	@echo "$(BLUE)📋 Planning secrets (GitHub token)...$(NC)"
	@cd $(CI_CD_DIR)/01-secrets && terragrunt plan
##@ CI/CD Deployment (00-ci-cd)

deploy-ci-cd: deploy-secrets deploy-ecr deploy-codebuild deploy-codepipeline ## Deploy entire CI/CD pipeline
	@echo "$(GREEN)✅ Full CI/CD pipeline deployed$(NC)"
	@echo "$(BLUE)Next steps:$(NC)"
	@echo "  1. git push origin dev"
	@echo "  2. Watch CodePipeline: https://console.aws.amazon.com/codesuite/codepipeline"
	@echo "  3. Check ECR for built images"

deploy-secrets: ## Deploy secrets (reads from .env or prompts)
	@echo "$(BLUE)🔐 [1/4] Deploying secrets (GitHub token)...$(NC)"
	@if [ -z "$$GITHUB_TOKEN_LAB_SCALING" ]; then \
		echo "$(YELLOW)⚠️  GITHUB_TOKEN_LAB_SCALING not in .env file$(NC)"; \
		echo "$(YELLOW)Get token from: https://github.com/settings/tokens?type=beta$(NC)"; \
		read -p "Enter GitHub Fine-Grained Token (hidden): " GITHUB_TOKEN_LAB_SCALING; \
	fi; \
	if [ -z "$$GITHUB_TOKEN_LAB_SCALING" ]; then \
		echo "$(RED)❌ Token cannot be empty$(NC)"; \
		exit 1; \
	fi; \
	export GITHUB_TOKEN_LAB_SCALING=$$GITHUB_TOKEN_LAB_SCALING; \
	cd $(CI_CD_DIR)/01-secrets && terragrunt apply
	@echo "$(GREEN)✅ Secrets deployed$(NC)"

plan-ecr: ## Plan ECR repository
	@echo "$(BLUE)📋 Planning ECR repository...$(NC)"
	@cd $(CI_CD_DIR)/02-ecr && terragrunt plan

deploy-ecr: ## Deploy ECR repository
	@echo "$(BLUE)🏗️ [2/4] Deploying ECR repository...$(NC)"
	@cd $(CI_CD_DIR)/02-ecr && terragrunt apply
	@echo "$(GREEN)✅ ECR deployed$(NC)"
	@echo "$(YELLOW)⚠ Ready for Docker images from CodeBuild$(NC)"

plan-alb: ## Plan Application Load Balancer (shared infrastructure)
	@echo "$(BLUE)📋 Planning ALB...$(NC)"
	@cd $(SHARED_INFRA_DIR)/03-alb && terragrunt plan

deploy-alb: ## Deploy Application Load Balancer (shared infrastructure)
	@echo "$(BLUE)🏗️ [3/3] Deploying Application Load Balancer...$(NC)"
	@cd $(SHARED_INFRA_DIR)/03-alb && terragrunt apply
	@echo "$(GREEN)✅ ALB deployed (shared by EC2 and ECS)$(NC)"
	@$(MAKE) get-alb-dns

plan-asg: ## Plan Auto Scaling Group
	@echo "$(BLUE)📋 Planning Auto Scaling Group...$(NC)"
	@cd $(ASG_DIR)/03-asg && terragrunt plan

deploy-asg-only: check-image ## Deploy Auto Scaling Group (without prerequisites)
	@echo "$(BLUE)🏗️ [3/6] Deploying Auto Scaling Group...$(NC)"
	@cd $(ASG_DIR)/03-asg && terragrunt apply
	@echo "$(GREEN)✅ ASG deployed$(NC)"
	@echo "$(YELLOW)⏳ Waiting for instances to become healthy...$(NC)"
	@sleep 30
	@$(MAKE) check-health || true

plan-cloudwatch: ## Plan CloudWatch alarms
	@echo "$(BLUE)📋 Planning CloudWatch alarms...$(NC)"
	@cd $(ASG_DIR)/04-cloudwatch && terragrunt plan

deploy-cloudwatch: ## Deploy CloudWatch alarms
	@echo "$(BLUE)🏗️ [4/6] Deploying CloudWatch alarms...$(NC)"
	@cd $(ASG_DIR)/04-cloudwatch && terragrunt apply
	@echo "$(GREEN)✅ CloudWatch alarms deployed$(NC)"

plan-eventbridge: ## Plan EventBridge rules
	@echo "$(BLUE)📋 Planning EventBridge rules...$(NC)"
	@cd $(ASG_DIR)/05-eventbridge && terragrunt plan

deploy-eventbridge: ## Deploy EventBridge rules
	@echo "$(BLUE)🏗️ [5/6] Deploying EventBridge rules...$(NC)"
	@cd $(ASG_DIR)/05-eventbridge && terragrunt apply
	@echo "$(GREEN)✅ EventBridge rules deployed$(NC)"

plan-dashboard: ## Plan CloudWatch dashboard
	@echo "$(BLUE)📋 Planning CloudWatch dashboard...$(NC)"
	@cd $(ASG_DIR)/06-dashboard && terragrunt plan

deploy-dashboard: ## Deploy CloudWatch dashboard
	@echo "$(BLUE)🏗️ [6/6] Deploying CloudWatch dashboard...$(NC)"
	@cd $(ASG_DIR)/06-dashboard && terragrunt apply
	@echo "$(GREEN)✅ Dashboard deployed$(NC)"
	@$(MAKE) dashboard

plan-codebuild: ## Plan CodeBuild project
	@echo "$(BLUE)📋 Planning CodeBuild project...$(NC)"
	@cd $(CI_CD_DIR)/03-codebuild && terragrunt plan

deploy-codebuild: ## Deploy CodeBuild project (reads from .env or prompts)
	@echo "$(BLUE)🏗️ Deploying CodeBuild project...$(NC)"
	@if [ -z "$$GITHUB_TOKEN_LAB_SCALING" ]; then \
		echo "$(YELLOW)⚠️  GITHUB_TOKEN_LAB_SCALING not in .env file$(NC)"; \
		echo "$(YELLOW)Get token from: https://github.com/settings/tokens$(NC)"; \
		echo "$(YELLOW)Permissions needed: repo (full), admin:repo_hook$(NC)"; \
		read -p "Enter GitHub Personal Access Token (hidden): " GITHUB_TOKEN_LAB_SCALING; \
	fi; \
	if [ -z "$$GITHUB_TOKEN_LAB_SCALING" ]; then \
		echo "$(RED)❌ Token cannot be empty$(NC)"; \
		exit 1; \
	fi; \
	export GITHUB_TOKEN_LAB_SCALING=$$GITHUB_TOKEN_LAB_SCALING; \
	cd $(CI_CD_DIR)/03-codebuild && terragrunt apply
	@echo "$(GREEN)✅ CodeBuild deployed$(NC)"

plan-codepipeline: ## Plan CodePipeline
	@echo "$(BLUE)📋 Planning CodePipeline...$(NC)"
	@cd $(CI_CD_DIR)/04-codepipeline && terragrunt plan

deploy-codepipeline: deploy-codebuild ## Deploy CodePipeline (reads from .env or prompts)
	@echo "$(BLUE)🔐 Setting up GitHub token for CodePipeline...$(NC)"
	@if [ -z "$$GITHUB_TOKEN_LAB_SCALING" ]; then \
		echo "$(YELLOW)⚠️  GITHUB_TOKEN_LAB_SCALING not in .env file$(NC)"; \
		echo "$(YELLOW)Get token from: https://github.com/settings/tokens$(NC)"; \
		echo "$(YELLOW)Permissions needed: repo (full), admin:repo_hook$(NC)"; \
		read -p "Enter GitHub Personal Access Token (hidden): " GITHUB_TOKEN_LAB_SCALING; \
	fi; \
	if [ -z "$$GITHUB_TOKEN_LAB_SCALING" ]; then \
		echo "$(RED)❌ Token cannot be empty$(NC)"; \
		exit 1; \
	fi; \
	export GITHUB_TOKEN_LAB_SCALING=$$GITHUB_TOKEN_LAB_SCALING; \
	export GITHUB_TOKEN=$$GITHUB_TOKEN_LAB_SCALING; \
	cd $(CI_CD_DIR)/01-secrets && terragrunt apply; \
	cd $(CI_CD_DIR)/04-codepipeline && terragrunt apply
	@echo "$(GREEN)✅ CodePipeline deployed$(NC)"
	@echo "$(BLUE)CI/CD Flow: GitHub push → CodePipeline → CodeBuild → ECR$(NC)"

get-alb-dns: ## Get ALB DNS name
	@echo "$(BLUE)📍 ALB DNS Name:$(NC)"
	@aws elbv2 describe-load-balancers \
		--names $(ALB_NAME) \
		--region $(AWS_REGION) \
		--query 'LoadBalancers[0].DNSName' \
		--output text 2>/dev/null || echo "$(YELLOW)⚠ ALB not found yet$(NC)"

check-health: ## Check ALB health endpoint
	@echo "$(BLUE)🏥 Checking ALB health...$(NC)"
	@bash -c 'ALB_DNS="$$(aws elbv2 describe-load-balancers --names $(ALB_NAME) --region $(AWS_REGION) --query "LoadBalancers[0].DNSName" --output text 2>/dev/null || true)"; if [ -n "$$ALB_DNS" ]; then \
		echo "Testing: http://$$ALB_DNS/healthz"; if curl -sSf http://$$ALB_DNS/healthz >/dev/null; then \
			printf "$(GREEN)✓ ALB health check passed$(NC)\n"; else \
			printf "$(YELLOW)⚠ Waiting for instances to become healthy...$(NC)\n"; fi; \
	else \
		printf "$(RED)❌ ALB not found$(NC)\n"; \
		printf "$(YELLOW)⚠ Deploy the ALB stack before re-running$(NC)\n"; fi'

##@ Testing

test-cpu: check-health ## Run CPU pressure test
	@echo "$(BLUE)🚀 Running CPU pressure test...$(NC)"
	@export BASE_URL=$$(aws elbv2 describe-load-balancers --names $(ALB_NAME) --region $(AWS_REGION) --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null | sed 's/^/http:\/\//') && \
		K6_PROMETHEUS_RW_SERVER_URL=$(K6_PROMETHEUS_RW_SERVER_URL) K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM=$(K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM) k6 run -o $(K6_OUTPUT) $(APPS_DIR)/load-generator/k6/cpu-pressure.js

test-rps: check-health ## Run RPS gradual ramp test
	@echo "$(BLUE)🚀 Running RPS gradual ramp test...$(NC)"
	@export BASE_URL=$$(aws elbv2 describe-load-balancers --names $(ALB_NAME) --region $(AWS_REGION) --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null | sed 's/^/http:\/\//') && \
		K6_PROMETHEUS_RW_SERVER_URL=$(K6_PROMETHEUS_RW_SERVER_URL) K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM=$(K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM) k6 run -o $(K6_OUTPUT) $(APPS_DIR)/load-generator/k6/gradual-ramp.js

test-memory: check-health ## Run memory pressure test
	@echo "$(BLUE)🚀 Running memory pressure test...$(NC)"
	@export BASE_URL=$$(aws elbv2 describe-load-balancers --names $(ALB_NAME) --region $(AWS_REGION) --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null | sed 's/^/http:\/\//') && \
		export MB=150 && \
		K6_PROMETHEUS_RW_SERVER_URL=$(K6_PROMETHEUS_RW_SERVER_URL) K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM=$(K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM) k6 run -o $(K6_OUTPUT) $(APPS_DIR)/load-generator/k6/memory-pressure.js

test-spike: check-health ## Run sudden spike test
	@echo "$(BLUE)🚀 Running sudden spike test...$(NC)"
	@export BASE_URL=$$(aws elbv2 describe-load-balancers --names $(ALB_NAME) --region $(AWS_REGION) --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null | sed 's/^/http:\/\//') && \
		K6_PROMETHEUS_RW_SERVER_URL=$(K6_PROMETHEUS_RW_SERVER_URL) K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM=$(K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM) k6 run -o $(K6_OUTPUT) $(APPS_DIR)/load-generator/k6/spike.js

test-sawtooth: check-health ## Run sawtooth cycle test
	@echo "$(BLUE)🚀 Running sawtooth cycle test...$(NC)"
	@export BASE_URL=$$(aws elbv2 describe-load-balancers --names $(ALB_NAME) --region $(AWS_REGION) --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null | sed 's/^/http:\/\//') && \
		K6_PROMETHEUS_RW_SERVER_URL=$(K6_PROMETHEUS_RW_SERVER_URL) K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM=$(K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM) k6 run -o $(K6_OUTPUT) $(APPS_DIR)/load-generator/k6/sawtooth.js

test-all: test-cpu test-rps test-spike ## Run all load tests sequentially

##@ Monitoring

monitoring-up: ## Start local Prometheus + Grafana
	@echo "$(BLUE)📈 Starting Prometheus + Grafana...$(NC)"
	@docker compose -f monitoring/docker-compose.yml up -d
	@echo "$(GREEN)✓ Grafana ready at http://localhost:3000$(NC)"

monitoring-down: ## Stop local Prometheus + Grafana
	@echo "$(BLUE)🛑 Stopping Prometheus + Grafana...$(NC)"
	@docker compose -f monitoring/docker-compose.yml down

monitoring-dashboard: ## Open local Grafana k6 dashboard
	@echo "$(BLUE)📊 Opening Grafana dashboard...$(NC)"
	@open "http://localhost:3000/d/k6-overview/k6-overview" || \
		echo "Visit: http://localhost:3000/d/k6-overview/k6-overview"

dashboard: ## Open CloudWatch Dashboard in browser
	@echo "$(BLUE)📊 Opening CloudWatch Dashboard...$(NC)"
	@open "https://$(AWS_REGION).console.aws.amazon.com/cloudwatch/home?region=$(AWS_REGION)#dashboards/dashboard/$(DASHBOARD_NAME)" || \
		echo "Visit: https://$(AWS_REGION).console.aws.amazon.com/cloudwatch/home?region=$(AWS_REGION)#dashboards/dashboard/$(DASHBOARD_NAME)"

logs: ## Tail EventBridge event logs
	@echo "$(BLUE)📋 Tailing EventBridge logs...$(NC)"
	@aws logs tail /aws/events/lab-scaling --follow --region $(AWS_REGION) 2>/dev/null || \
		echo "$(YELLOW)⚠ Log group not found. Deploy EventBridge stack first.$(NC)"

logs-codebuild: ## Tail CodeBuild logs
	@echo "$(BLUE)📋 Tailing CodeBuild logs...$(NC)"
	@aws logs tail /aws/codebuild/lab-target-app-build --follow --region $(AWS_REGION) 2>/dev/null || \
		echo "$(YELLOW)⚠ CodeBuild log group not found$(NC)"

watch-asg: ## Watch ASG instance count (updates every 10s)
	@echo "$(BLUE)👀 Watching ASG instance count (Ctrl+C to stop)...$(NC)"
	@while true; do \
		clear; \
		echo "$(BLUE)ASG Instance Status:$(NC)"; \
		aws autoscaling describe-auto-scaling-groups \
			--auto-scaling-group-names lab-asg-asg \
			--region $(AWS_REGION) \
			--query 'AutoScalingGroups[0].[DesiredCapacity,MinSize,MaxSize]' \
			--output text 2>/dev/null | awk '{print "Desired: "$$1" | Min: "$$2" | Max: "$$3}' || echo "$(RED)ASG not found$(NC)"; \
		echo ""; \
		aws autoscaling describe-auto-scaling-groups \
			--auto-scaling-group-names lab-asg-asg \
			--region $(AWS_REGION) \
			--query 'AutoScalingGroups[0].Instances[*].[InstanceId,HealthStatus,LifecycleState]' \
			--output table 2>/dev/null || echo "$(YELLOW)No instances$(NC)"; \
		sleep 10; \
	done

##@ Cleanup

destroy: ## Destroy all infrastructure
	@echo "$(RED)🗑️ Destroying all infrastructure...$(NC)"
	@read -p "Are you sure? Type 'yes' to confirm: " confirm && [ "$$confirm" = "yes" ] || (echo "Aborted" && exit 1)
	@cd $(ASG_DIR) && terragrunt run-all destroy --terragrunt-non-interactive
	@echo "$(GREEN)✅ All infrastructure destroyed$(NC)"

destroy-sequential: ## Destroy stacks in reverse order (safer)
	@echo "$(RED)🗑️ Destroying infrastructure in reverse order...$(NC)"
	@read -p "Are you sure? Type 'yes' to confirm: " confirm && [ "$$confirm" = "yes" ] || (echo "Aborted" && exit 1)
	@cd $(ASG_DIR)/06-dashboard && terragrunt destroy -auto-approve || true
	@cd $(ASG_DIR)/05-eventbridge && terragrunt destroy -auto-approve || true
	@cd $(ASG_DIR)/04-cloudwatch && terragrunt destroy -auto-approve || true
	@cd $(ASG_DIR)/03-asg && terragrunt destroy -auto-approve || true
	@cd $(SHARED_INFRA_DIR)/03-alb && terragrunt destroy -auto-approve || true
	@cd $(ASG_DIR)/02-instance-sg && terragrunt destroy -auto-approve || true
	@cd $(SHARED_INFRA_DIR)/02-alb-sg && terragrunt destroy -auto-approve || true
	@cd $(SHARED_INFRA_DIR)/01-networking && terragrunt destroy -auto-approve || true
	@cd $(ASG_DIR)/01-iam && terragrunt destroy -auto-approve || true

##@ Individual Stack Destroy

destroy-dashboard: ## Destroy CloudWatch dashboard
	@echo "$(RED)🗑️ Destroying dashboard...$(NC)"
	@cd $(ASG_DIR)/06-dashboard && terragrunt destroy -auto-approve

destroy-eventbridge: ## Destroy EventBridge rules
	@echo "$(RED)🗑️ Destroying EventBridge...$(NC)"
	@cd $(ASG_DIR)/05-eventbridge && terragrunt destroy -auto-approve

destroy-cloudwatch: ## Destroy CloudWatch alarms
	@echo "$(RED)🗑️ Destroying CloudWatch alarms...$(NC)"
	@cd $(ASG_DIR)/04-cloudwatch && terragrunt destroy -auto-approve

destroy-asg: ## Destroy Auto Scaling Group
	@echo "$(RED)🗑️ Destroying ASG...$(NC)"
	@cd $(ASG_DIR)/03-asg && terragrunt destroy -auto-approve

destroy-alb: ## Destroy Application Load Balancer (shared infrastructure)
	@echo "$(RED)🗑️ Destroying ALB...$(NC)"
	@cd $(SHARED_INFRA_DIR)/03-alb && terragrunt destroy -auto-approve

destroy-instance-sg: ## Destroy instance security group
	@echo "$(RED)🗑️ Destroying instance security group...$(NC)"
	@cd $(ASG_DIR)/02-instance-sg && terragrunt destroy -auto-approve

destroy-security-groups: ## Destroy ALB security group (shared infrastructure)
	@echo "$(RED)🗑️ Destroying ALB security group...$(NC)"
	@cd $(SHARED_INFRA_DIR)/02-alb-sg && terragrunt destroy -auto-approve

destroy-networking: ## Destroy VPC and networking (shared infrastructure)
	@echo "$(RED)🗑️ Destroying networking (NAT Gateway will be removed)...$(NC)"
	@cd $(SHARED_INFRA_DIR)/01-networking && terragrunt destroy -auto-approve

destroy-iam: ## Destroy IAM instance profile
	@echo "$(RED)🗑️ Destroying IAM...$(NC)"
	@cd $(ASG_DIR)/01-iam && terragrunt destroy -auto-approve

destroy-ecr: ## Destroy ECR repository
	@echo "$(RED)🗑️ Destroying ECR...$(NC)"
	@cd $(CI_CD_DIR)/02-ecr && terragrunt destroy -auto-approve
	@echo "$(GREEN)✅ All infrastructure destroyed$(NC)"

clean: ## Clean Terraform cache files
	@echo "$(BLUE)🧹 Cleaning Terraform cache...$(NC)"
	@find $(ASG_DIR) -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@find $(CI_CD_DIR) -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@find $(ASG_DIR) -type d -name ".terragrunt-cache" -exec rm -rf {} + 2>/dev/null || true
	@find $(CI_CD_DIR) -type d -name ".terragrunt-cache" -exec rm -rf {} + 2>/dev/null || true
	@find $(ASG_DIR) -type f -name "*.tfstate*" -delete 2>/dev/null || true
	@find $(CI_CD_DIR) -type f -name "*.tfstate*" -delete 2>/dev/null || true
	@echo "$(GREEN)✓ Cache cleaned$(NC)"

##@ Complete Workflows

all: validate build deploy-all check-health ## Run complete pipeline (validate → build → deploy)
	@echo "$(GREEN)✅ Complete pipeline finished!$(NC)"
	@echo "$(BLUE)Next steps:$(NC)"
	@echo "  1. Run load tests: make test-all"
	@echo "  2. Monitor dashboard: make dashboard"
	@echo "  3. Watch ASG scaling: make watch-asg"

step-by-step: ## Interactive step-by-step deployment guide
	@echo "$(BLUE)╔════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(BLUE)║  Step-by-Step Deployment Guide                            ║$(NC)"
	@echo "$(BLUE)╚════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(YELLOW)Step 1: Validate modules$(NC)"
	@echo "  make validate"
	@echo ""
	@echo "$(YELLOW)Step 2: Deploy IAM (instance profile)$(NC)"
	@echo "  make plan-iam        # Preview changes"
	@echo "  make deploy-iam      # Apply"
	@echo ""
	@echo "$(YELLOW)Step 3: Deploy Shared Infrastructure (VPC, ALB)$(NC)"
	@echo "  make plan-shared-infra   # Preview all shared components"
	@echo "  make deploy-shared-infra # Deploy networking + ALB (shared by EC2/ECS/EKS)"
	@echo ""
	@echo "$(YELLOW)Step 4: Deploy EC2 Instance Security Group$(NC)"
	@echo "  make plan-instance-sg"
	@echo "  make deploy-instance-sg"
	@echo ""
	@echo "$(YELLOW)Step 5: Deploy ECR repository$(NC)"
	@echo "  make plan-ecr"
	@echo "  make deploy-ecr"
	@echo ""
	@echo "$(YELLOW)Step 6: Build Docker image$(NC)"
	@echo "  make build           # Build and push to ECR"
	@echo ""
	@echo "$(YELLOW)Step 7: Deploy ASG$(NC)"
	@echo "  (ALB already deployed in Step 3 as shared infrastructure)"
	@echo "  make plan-asg"
	@echo "  make deploy-asg-only  # Will auto-check image exists"
	@echo ""
	@echo "$(YELLOW)Step 8: Deploy Monitoring$(NC)"
	@echo "  make plan-cloudwatch"
	@echo "  make deploy-cloudwatch"
	@echo "  make plan-eventbridge"
	@echo "  make deploy-eventbridge"
	@echo "  make plan-dashboard"
	@echo "  make deploy-dashboard"
	@echo ""
	@echo "$(YELLOW)Step 9: (Optional) Deploy CodeBuild$(NC)"
	@echo "  make plan-codebuild"
	@echo "  make deploy-codebuild"
	@echo ""
	@echo "$(GREEN)Ready to start? Run: make deploy-iam$(NC)"

demo: all test-cpu ## Full demo: deploy + CPU test + open dashboard
	@echo "$(BLUE)🎬 Opening dashboard for monitoring...$(NC)"
	@$(MAKE) dashboard
	@echo "$(GREEN)✅ Demo complete!$(NC)"

status: ## Show current deployment status
	@echo "$(BLUE)📊 Deployment Status$(NC)"
	@echo ""
	@echo "$(YELLOW)ALB:$(NC)"
	@$(MAKE) get-alb-dns || true
	@echo ""
	@echo "$(YELLOW)ASG Instances:$(NC)"
	@aws autoscaling describe-auto-scaling-groups \
		--auto-scaling-group-names lab-asg-asg \
		--region $(AWS_REGION) \
		--query 'AutoScalingGroups[0].Instances[*].[InstanceId,HealthStatus,LifecycleState]' \
		--output table 2>/dev/null || echo "$(RED)❌ ASG not found$(NC)"
	@echo ""
	@echo "$(YELLOW)ECR Images:$(NC)"
	@aws ecr describe-images \
		--repository-name $(ECR_REPO_NAME) \
		--region $(AWS_REGION) \
		--query 'imageDetails[*].[imageTags[0],imagePushedAt]' \
		--output table 2>/dev/null || echo "$(RED)❌ No images found$(NC)"
