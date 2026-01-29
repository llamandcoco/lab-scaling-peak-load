.PHONY: plan-ecs deploy-ecs destroy-ecs

##@ ECS Fargate Deployment (11-ecs-fargate)

plan-ecs: ## Plan ECS Fargate stacks
	@echo "$(BLUE)📋 Planning ECS Fargate stacks...$(NC)"
	@cd $(ECS_DIR) && terragrunt run --all --queue-exclude-external --non-interactive -- plan $(TG_PLAN_ARGS)

deploy-ecs: deploy-shared-infra check-image ## Deploy ECS Fargate stacks (requires shared-infra)
	@echo "$(BLUE)🏗️ Deploying ECS Fargate stacks...$(NC)"
	@cd $(ECS_DIR) && terragrunt run --all --queue-exclude-external --non-interactive -- apply $(TG_APPLY_ARGS)
	@echo "$(GREEN)✅ ECS Fargate deployed$(NC)"
	@echo "$(BLUE)Test ECS via ALB:$(NC)"
	@echo "  ALB_DNS=$$(aws elbv2 describe-load-balancers --names $(ALB_NAME) --region $(AWS_REGION) --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null)"
	@echo "  curl http://$$ALB_DNS/healthz"

destroy-ecs: ## Destroy ECS Fargate stacks
	@echo "$(RED)🗑️ Destroying ECS Fargate stacks...$(NC)"
	@cd $(ECS_DIR) && terragrunt run --all --queue-exclude-external --non-interactive -- destroy $(TG_DESTROY_ARGS)
