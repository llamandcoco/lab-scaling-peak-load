.PHONY: deploy-ci-cd deploy-secrets deploy-ecr deploy-codebuild deploy-codepipeline plan-secrets plan-ecr plan-codebuild plan-codepipeline

##@ CI/CD Deployment (00-ci-cd)

deploy-ci-cd: deploy-secrets deploy-ecr deploy-codebuild deploy-codepipeline ## Deploy entire CI/CD pipeline
	@echo "$(GREEN)✅ Full CI/CD pipeline deployed$(NC)"
	@echo "$(BLUE)Next steps:$(NC)"
	@echo "  1. git push origin dev"
	@echo "  2. Watch CodePipeline: https://console.aws.amazon.com/codesuite/codepipeline"
	@echo "  3. Check ECR for built images"

plan-secrets: ## Plan secrets stack
	@echo "$(BLUE)📋 Planning secrets (GitHub token)...$(NC)"
	@cd $(CI_CD_DIR)/01-secrets && terragrunt plan $(TG_PLAN_ARGS)

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
	cd $(CI_CD_DIR)/01-secrets && terragrunt apply $(TG_APPLY_ARGS)
	@echo "$(GREEN)✅ Secrets deployed$(NC)"

plan-ecr: ## Plan ECR repository
	@echo "$(BLUE)📋 Planning ECR repository...$(NC)"
	@cd $(CI_CD_DIR)/02-ecr && terragrunt plan $(TG_PLAN_ARGS)

deploy-ecr: ## Deploy ECR repository
	@echo "$(BLUE)🏗️ [2/4] Deploying ECR repository...$(NC)"
	@cd $(CI_CD_DIR)/02-ecr && terragrunt apply $(TG_APPLY_ARGS)
	@echo "$(GREEN)✅ ECR deployed$(NC)"
	@echo "$(YELLOW)⚠ Ready for Docker images from CodeBuild$(NC)"

plan-codebuild: ## Plan CodeBuild project
	@echo "$(BLUE)📋 Planning CodeBuild project...$(NC)"
	@cd $(CI_CD_DIR)/03-codebuild && terragrunt plan $(TG_PLAN_ARGS)

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
	cd $(CI_CD_DIR)/03-codebuild && terragrunt apply $(TG_APPLY_ARGS)
	@echo "$(GREEN)✅ CodeBuild deployed$(NC)"

plan-codepipeline: ## Plan CodePipeline
	@echo "$(BLUE)📋 Planning CodePipeline...$(NC)"
	@cd $(CI_CD_DIR)/04-codepipeline && terragrunt plan $(TG_PLAN_ARGS)

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
	cd $(CI_CD_DIR)/01-secrets && terragrunt apply $(TG_APPLY_ARGS); \
	cd $(CI_CD_DIR)/04-codepipeline && terragrunt apply $(TG_APPLY_ARGS)
	@echo "$(GREEN)✅ CodePipeline deployed$(NC)"
	@echo "$(BLUE)CI/CD Flow: GitHub push → CodePipeline → CodeBuild → ECR$(NC)"
