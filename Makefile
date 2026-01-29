PROJECT_ROOT := $(CURDIR)

include makefiles/common.mk
include makefiles/shared.mk
include makefiles/ec2.mk
include makefiles/ecs.mk
include makefiles/ci.mk
include makefiles/tests.mk
include makefiles/monitoring.mk
include makefiles/cleanup.mk
include makefiles/workflows.mk
