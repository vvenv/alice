// 蓝绿部署由 scripts/lib/blue-green.sh 按槽位启动（alice-a / alice-b 等）。
module.exports = {
  apps: [
    {
      name: "alice",
      script: "./packages/server/dist/index.js",
      instances: 1,
      exec_mode: "fork",
      autorestart: true,
      watch: false,
      max_memory_restart: "512M",
      env: {
        NODE_ENV: "production",
      },
      error_file: "./logs/pm2-error.log",
      out_file: "./logs/pm2-out.log",
      log_date_format: "YYYY-MM-DD HH:mm:ss Z",
      merge_logs: true,
    },
    {
      name: "alice-test",
      script: "./packages/server/dist/index.js",
      instances: 1,
      exec_mode: "fork",
      autorestart: true,
      watch: false,
      max_memory_restart: "256M",
      env: {
        NODE_ENV: "test",
      },
      error_file: "./logs/pm2-test-error.log",
      out_file: "./logs/pm2-test-out.log",
      log_date_format: "YYYY-MM-DD HH:mm:ss Z",
      merge_logs: true,
    },
  ],
};
