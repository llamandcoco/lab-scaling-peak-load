.PHONY: monitoring-up monitoring-down monitoring-dashboard dashboard logs logs-codebuild watch-asg

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
