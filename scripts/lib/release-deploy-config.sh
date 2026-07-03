# 本地 release 构建与 SSH 部署的项目配置
# 同步到 sibling 仓库时仅修改本文件

PROJECT_SLUG=alice
REMOTE_STAGING_DIR=/tmp/alice-deploy
BOOTSTRAP_REMOTE_STAGING_DIR=/tmp/alice-bootstrap
HEALTH_CHECK_SLOT_DIRS="/var/www/alice_a /var/www/alice_b /var/www/alice_test_a /var/www/alice_test_b"
DEPLOY_OVERRIDE_PREFIX=ALICE
