.PHONY: deploy-shared-infra plan-shared-infra destroy-shared-infra plan-networking deploy-networking plan-security-groups deploy-security-groups plan-alb deploy-alb

##@ Shared Infrastructure (00-shared-infra)

deploy-shared-infra: ## Deploy all shared infrastructure (networking, ALB SG, ALB)
	@echo "$(BLUE)🏗️ Deploying shared infrastructure...$(NC)"
	@cd $(SHARED_INFRA_DIR)/01-networking && terragrunt apply $(TG_APPLY_ARGS)
	@cd $(SHARED_INFRA_DIR)/02-alb-sg && terragrunt apply $(TG_APPLY_ARGS)
	@cd $(SHARED_INFRA_DIR)/03-alb && terragrunt apply $(TG_APPLY_ARGS)
	@echo "$(GREEN)✅ Shared infrastructure deployed (ready for EC2/ECS/EKS)$(NC)"
	@$(MAKE) get-alb-dns

plan-shared-infra: ## Plan all shared infrastructure
	@echo "$(BLUE)📋 Planning shared infrastructure...$(NC)"
	@cd $(SHARED_INFRA_DIR)/01-networking && terragrunt plan $(TG_PLAN_ARGS)
	@cd $(SHARED_INFRA_DIR)/02-alb-sg && terragrunt plan $(TG_PLAN_ARGS)
	@cd $(SHARED_INFRA_DIR)/03-alb && terragrunt plan $(TG_PLAN_ARGS)

destroy-shared-infra: ## Destroy shared infrastructure (WARNING: affects all platforms)
	@echo "$(RED)🗑️ Destroying shared infrastructure...$(NC)"
	@echo "$(YELLOW)⚠️  This will affect EC2, ECS, and EKS platforms!$(NC)"
	@cd $(SHARED_INFRA_DIR)/03-alb && terragrunt destroy $(TG_DESTROY_ARGS) || true
	@cd $(SHARED_INFRA_DIR)/02-alb-sg && terragrunt destroy $(TG_DESTROY_ARGS) || true
	@cd $(SHARED_INFRA_DIR)/01-networking && terragrunt destroy $(TG_DESTROY_ARGS) || true
	@echo "$(GREEN)✅ Shared infrastructure destroyed$(NC)"

plan-networking: ## Plan networking stack (shared infrastructure)
	@echo "$(BLUE)📋 Planning networking stack...$(NC)"
	@cd $(SHARED_INFRA_DIR)/01-networking && terragrunt plan $(TG_PLAN_ARGS)

deploy-networking: ## Deploy VPC and subnets (shared infrastructure)
	@echo "$(BLUE)🏗️ [1/3] Deploying VPC and subnets...$(NC)"
	@cd $(SHARED_INFRA_DIR)/01-networking && terragrunt apply $(TG_APPLY_ARGS)
	@echo "$(GREEN)✅ Networking deployed (shared across EC2/ECS/EKS)$(NC)"

plan-security-groups: ## Plan ALB security group (shared infrastructure)
	@echo "$(BLUE)📋 Planning ALB security group...$(NC)"
	@cd $(SHARED_INFRA_DIR)/02-alb-sg && terragrunt plan $(TG_PLAN_ARGS)

deploy-security-groups: ## Deploy ALB security group (shared infrastructure)
	@echo "$(BLUE)🏗️ [2/3] Deploying ALB security group...$(NC)"
	@cd $(SHARED_INFRA_DIR)/02-alb-sg && terragrunt apply $(TG_APPLY_ARGS)
	@echo "$(GREEN)✅ ALB security group deployed (shared across EC2/ECS)$(NC)"

plan-alb: ## Plan Application Load Balancer (shared infrastructure)
	@echo "$(BLUE)📋 Planning ALB...$(NC)"
	@cd $(SHARED_INFRA_DIR)/03-alb && terragrunt plan $(TG_PLAN_ARGS)

deploy-alb: ## Deploy Application Load Balancer (shared infrastructure)
	@echo "$(BLUE)🏗️ [3/3] Deploying Application Load Balancer...$(NC)"
	@cd $(SHARED_INFRA_DIR)/03-alb && terragrunt apply $(TG_APPLY_ARGS)
	@echo "$(GREEN)✅ ALB deployed (shared by EC2 and ECS)$(NC)"
	@$(MAKE) get-alb-dns
