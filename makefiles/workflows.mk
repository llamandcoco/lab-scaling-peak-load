.PHONY: all step-by-step demo status

##@ Complete Workflows

all: validate build deploy-all check-health-ec2 ## Run complete pipeline (validate → build → deploy)
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
	@echo "$(YELLOW)Step 5: Deploy EC2 Target Group$(NC)"
	@echo "  make plan-ec2-tg"
	@echo "  make deploy-ec2-tg"
	@echo ""
	@echo "$(YELLOW)Step 6: Deploy ECR repository$(NC)"
	@echo "  make plan-ecr"
	@echo "  make deploy-ecr"
	@echo ""
	@echo "$(YELLOW)Step 7: Build Docker image$(NC)"
	@echo "  make build           # Build and push to ECR"
	@echo ""
	@echo "$(YELLOW)Step 8: Deploy ASG$(NC)"
	@echo "  (ALB already deployed in Step 3 as shared infrastructure)"
	@echo "  make plan-asg"
	@echo "  make deploy-asg-only  # Will auto-check image exists"
	@echo ""
	@echo "$(YELLOW)Step 9: Deploy Monitoring$(NC)"
	@echo "  make plan-cloudwatch"
	@echo "  make deploy-cloudwatch"
	@echo "  make plan-eventbridge"
	@echo "  make deploy-eventbridge"
	@echo "  make plan-dashboard"
	@echo "  make deploy-dashboard"
	@echo ""
	@echo "$(YELLOW)Step 10: (Optional) Deploy CodeBuild$(NC)"
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
