.PHONY: destroy destroy-alb destroy-security-groups destroy-networking destroy-ecr clean

##@ Cleanup

destroy: ## Destroy all infrastructure
	@echo "$(RED)🗑️ Destroying all infrastructure...$(NC)"
	@cd $(ASG_DIR) && terragrunt run --all --queue-exclude-external --non-interactive -- destroy $(TG_DESTROY_ARGS)
	@echo "$(GREEN)✅ All infrastructure destroyed$(NC)"

##@ Individual Stack Destroy

destroy-alb: ## Destroy Application Load Balancer (shared infrastructure)
	@echo "$(RED)🗑️ Destroying ALB...$(NC)"
	@cd $(SHARED_INFRA_DIR)/03-alb && terragrunt destroy $(TG_DESTROY_ARGS)

destroy-security-groups: ## Destroy ALB security group (shared infrastructure)
	@echo "$(RED)🗑️ Destroying ALB security group...$(NC)"
	@cd $(SHARED_INFRA_DIR)/02-alb-sg && terragrunt destroy $(TG_DESTROY_ARGS)

destroy-networking: ## Destroy VPC and networking (shared infrastructure)
	@echo "$(RED)🗑️ Destroying networking (NAT Gateway will be removed)...$(NC)"
	@cd $(SHARED_INFRA_DIR)/01-networking && terragrunt destroy $(TG_DESTROY_ARGS)

destroy-ecr: ## Destroy ECR repository
	@echo "$(RED)🗑️ Destroying ECR...$(NC)"
	@cd $(CI_CD_DIR)/02-ecr && terragrunt destroy $(TG_DESTROY_ARGS)
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
