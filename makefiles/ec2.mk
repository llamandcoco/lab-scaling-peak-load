.PHONY: deploy-all deploy-ec2-asg-all deploy-ec2-asg deploy-asg plan-iam deploy-iam plan-instance-sg deploy-instance-sg plan-ec2-tg deploy-ec2-tg plan-asg plan-cloudwatch deploy-cloudwatch plan-eventbridge deploy-eventbridge plan-dashboard deploy-dashboard destroy-ec2-asg destroy-dashboard destroy-eventbridge destroy-cloudwatch destroy-asg destroy-ec2-tg destroy-instance-sg destroy-iam

##@ Deploy

deploy-all: ## Deploy entire infrastructure (all stacks)
	@echo "$(BLUE)🏗️ Deploying all infrastructure stacks...$(NC)"
	@cd $(ASG_DIR) && terragrunt run --all --queue-exclude-external --non-interactive -- apply $(TG_APPLY_ARGS)
	@echo "$(GREEN)✅ All stacks deployed$(NC)"
	@$(MAKE) get-alb-dns

##@ ASG EC2 Deployment (10-ec2-asg)

deploy-ec2-asg-all: deploy-shared-infra deploy-ec2-asg ## Deploy shared-infra + full EC2 ASG stack
	@echo "$(GREEN)✅ Complete EC2 infrastructure deployed$(NC)"

deploy-ec2-asg: deploy-iam deploy-instance-sg deploy-ec2-tg deploy-asg deploy-cloudwatch deploy-eventbridge deploy-dashboard ## Deploy ALL 10-ec2-asg stacks (IAM/SG/TG/ASG/CloudWatch/EventBridge/Dashboard)
	@echo "$(GREEN)✅ Full EC2 ASG stack deployed$(NC)"
	@echo "$(BLUE)Next steps:$(NC)"
	@echo "  1. Watch ASG: https://console.aws.amazon.com/ec2/v2/home#AutoScalingGroups"
	@echo "  2. Check health: make check-health-ec2"
	@echo "  3. Run tests: make test-cpu"

plan-iam: ## Plan IAM stack
	@echo "$(BLUE)📋 Planning IAM stack...$(NC)"
	@cd $(ASG_DIR)/01-iam && terragrunt plan $(TG_PLAN_ARGS)

deploy-iam: ## Deploy IAM instance profile
	@echo "$(BLUE)🏗️ [1/7] Deploying IAM instance profile...$(NC)"
	@cd $(ASG_DIR)/01-iam && terragrunt apply $(TG_APPLY_ARGS)
	@echo "$(GREEN)✅ IAM deployed$(NC)"

plan-instance-sg: ## Plan instance security group
	@echo "$(BLUE)📋 Planning instance security group...$(NC)"
	@cd $(ASG_DIR)/02-instance-sg && terragrunt plan $(TG_PLAN_ARGS)

deploy-instance-sg: ## Deploy instance security group
	@echo "$(BLUE)🏗️ [2/7] Deploying instance security group...$(NC)"
	@cd $(ASG_DIR)/02-instance-sg && terragrunt apply $(TG_APPLY_ARGS)
	@echo "$(GREEN)✅ Instance security group deployed$(NC)"

plan-ec2-tg: ## Plan EC2 ALB target group + listener rule
	@echo "$(BLUE)📋 Planning EC2 target group...$(NC)"
	@cd $(EC2_TG_DIR) && terragrunt plan $(TG_PLAN_ARGS)

deploy-ec2-tg: ## Deploy EC2 ALB target group + listener rule
	@echo "$(BLUE)🏗️ [3/7] Deploying EC2 target group...$(NC)"
	@cd $(EC2_TG_DIR) && terragrunt apply $(TG_APPLY_ARGS)
	@echo "$(GREEN)✅ EC2 target group deployed$(NC)"

plan-asg: ## Plan Auto Scaling Group
	@echo "$(BLUE)📋 Planning Auto Scaling Group...$(NC)"
	@cd $(ASG_DIR)/03-asg && terragrunt plan $(TG_PLAN_ARGS)

deploy-asg: check-image ## Deploy ONLY the Auto Scaling Group (requires EC2 target group)
	@echo "$(BLUE)🏗️ Deploying Auto Scaling Group...$(NC)"
	@cd $(ASG_DIR)/03-asg && terragrunt apply $(TG_APPLY_ARGS)
	@echo "$(GREEN)✅ ASG deployed$(NC)"
	@echo "$(YELLOW)⏳ Waiting for instances to become healthy...$(NC)"
	@sleep 30
	@$(MAKE) check-health-ec2 || true

plan-cloudwatch: ## Plan CloudWatch alarms
	@echo "$(BLUE)📋 Planning CloudWatch alarms...$(NC)"
	@cd $(ASG_DIR)/04-cloudwatch && terragrunt plan $(TG_PLAN_ARGS)

deploy-cloudwatch: ## Deploy CloudWatch alarms
	@echo "$(BLUE)🏗️ [5/7] Deploying CloudWatch alarms...$(NC)"
	@cd $(ASG_DIR)/04-cloudwatch && terragrunt apply $(TG_APPLY_ARGS)
	@echo "$(GREEN)✅ CloudWatch alarms deployed$(NC)"

plan-eventbridge: ## Plan EventBridge rules
	@echo "$(BLUE)📋 Planning EventBridge rules...$(NC)"
	@cd $(ASG_DIR)/05-eventbridge && terragrunt plan $(TG_PLAN_ARGS)

deploy-eventbridge: ## Deploy EventBridge rules
	@echo "$(BLUE)🏗️ [6/7] Deploying EventBridge rules...$(NC)"
	@cd $(ASG_DIR)/05-eventbridge && terragrunt apply $(TG_APPLY_ARGS)
	@echo "$(GREEN)✅ EventBridge rules deployed$(NC)"

plan-dashboard: ## Plan CloudWatch dashboard
	@echo "$(BLUE)📋 Planning CloudWatch dashboard...$(NC)"
	@cd $(ASG_DIR)/06-dashboard && terragrunt plan $(TG_PLAN_ARGS)

deploy-dashboard: ## Deploy CloudWatch dashboard
	@echo "$(BLUE)🏗️ [7/7] Deploying CloudWatch dashboard...$(NC)"
	@cd $(ASG_DIR)/06-dashboard && terragrunt apply $(TG_APPLY_ARGS)
	@echo "$(GREEN)✅ Dashboard deployed$(NC)"
	@$(MAKE) dashboard

##@ Individual Stack Destroy

destroy-ec2-asg: destroy-dashboard destroy-eventbridge destroy-cloudwatch destroy-asg destroy-ec2-tg destroy-instance-sg destroy-iam ## Destroy ALL 10-ec2-asg stacks (IAM/SG/TG/ASG/CloudWatch/EventBridge/Dashboard)
	@echo "$(GREEN)✅ EC2 ASG stack destroyed$(NC)"

destroy-dashboard: ## Destroy CloudWatch dashboard
	@echo "$(RED)🗑️ Destroying dashboard...$(NC)"
	@cd $(ASG_DIR)/06-dashboard && terragrunt destroy $(TG_DESTROY_ARGS)

destroy-eventbridge: ## Destroy EventBridge rules
	@echo "$(RED)🗑️ Destroying EventBridge...$(NC)"
	@cd $(ASG_DIR)/05-eventbridge && terragrunt destroy $(TG_DESTROY_ARGS)

destroy-cloudwatch: ## Destroy CloudWatch alarms
	@echo "$(RED)🗑️ Destroying CloudWatch alarms...$(NC)"
	@cd $(ASG_DIR)/04-cloudwatch && terragrunt destroy $(TG_DESTROY_ARGS)

destroy-asg: ## Destroy Auto Scaling Group
	@echo "$(RED)🗑️ Destroying ASG...$(NC)"
	@cd $(ASG_DIR)/03-asg && terragrunt destroy $(TG_DESTROY_ARGS)

destroy-ec2-tg: ## Destroy EC2 target group + listener rule
	@echo "$(RED)🗑️ Destroying EC2 target group...$(NC)"
	@cd $(EC2_TG_DIR) && terragrunt destroy $(TG_DESTROY_ARGS)

destroy-instance-sg: ## Destroy instance security group
	@echo "$(RED)🗑️ Destroying instance security group...$(NC)"
	@cd $(ASG_DIR)/02-instance-sg && terragrunt destroy $(TG_DESTROY_ARGS)

destroy-iam: ## Destroy IAM instance profile
	@echo "$(RED)🗑️ Destroying IAM...$(NC)"
	@cd $(ASG_DIR)/01-iam && terragrunt destroy $(TG_DESTROY_ARGS)
