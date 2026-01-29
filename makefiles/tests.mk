.PHONY: test-cpu test-rps test-memory test-spike test-sawtooth test-all

##@ Testing

test-cpu: check-health-ec2 ## Run CPU pressure test
	@echo "$(BLUE)🚀 Running CPU pressure test...$(NC)"
	@export BASE_URL=$$(aws elbv2 describe-load-balancers --names $(ALB_NAME) --region $(AWS_REGION) --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null | sed 's/^/http:\/\//') && \
		K6_PROMETHEUS_RW_SERVER_URL=$(K6_PROMETHEUS_RW_SERVER_URL) K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM=$(K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM) k6 run -o $(K6_OUTPUT) $(APPS_DIR)/load-generator/k6/cpu-pressure.js

test-rps: check-health-ec2 ## Run RPS gradual ramp test
	@echo "$(BLUE)🚀 Running RPS gradual ramp test...$(NC)"
	@export BASE_URL=$$(aws elbv2 describe-load-balancers --names $(ALB_NAME) --region $(AWS_REGION) --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null | sed 's/^/http:\/\//') && \
		K6_PROMETHEUS_RW_SERVER_URL=$(K6_PROMETHEUS_RW_SERVER_URL) K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM=$(K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM) k6 run -o $(K6_OUTPUT) $(APPS_DIR)/load-generator/k6/gradual-ramp.js

test-memory: check-health-ec2 ## Run memory pressure test
	@echo "$(BLUE)🚀 Running memory pressure test...$(NC)"
	@export BASE_URL=$$(aws elbv2 describe-load-balancers --names $(ALB_NAME) --region $(AWS_REGION) --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null | sed 's/^/http:\/\//') && \
		export MB=150 && \
		K6_PROMETHEUS_RW_SERVER_URL=$(K6_PROMETHEUS_RW_SERVER_URL) K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM=$(K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM) k6 run -o $(K6_OUTPUT) $(APPS_DIR)/load-generator/k6/memory-pressure.js

test-spike: check-health-ec2 ## Run sudden spike test
	@echo "$(BLUE)🚀 Running sudden spike test...$(NC)"
	@export BASE_URL=$$(aws elbv2 describe-load-balancers --names $(ALB_NAME) --region $(AWS_REGION) --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null | sed 's/^/http:\/\//') && \
		K6_PROMETHEUS_RW_SERVER_URL=$(K6_PROMETHEUS_RW_SERVER_URL) K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM=$(K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM) k6 run -o $(K6_OUTPUT) $(APPS_DIR)/load-generator/k6/spike.js

test-sawtooth: check-health-ec2 ## Run sawtooth cycle test
	@echo "$(BLUE)🚀 Running sawtooth cycle test...$(NC)"
	@export BASE_URL=$$(aws elbv2 describe-load-balancers --names $(ALB_NAME) --region $(AWS_REGION) --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null | sed 's/^/http:\/\//') && \
		K6_PROMETHEUS_RW_SERVER_URL=$(K6_PROMETHEUS_RW_SERVER_URL) K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM=$(K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM) k6 run -o $(K6_OUTPUT) $(APPS_DIR)/load-generator/k6/sawtooth.js

test-all: test-cpu test-rps test-spike ## Run all load tests sequentially
