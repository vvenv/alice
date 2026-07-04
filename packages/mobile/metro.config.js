const { getDefaultConfig } = require("@expo/metro-config");
const path = require("path");

const projectRoot = __dirname;
const workspaceRoot = path.resolve(projectRoot, "../..");

const config = getDefaultConfig(projectRoot);

// pnpm monorepo: watch the shared package for changes
config.watchFolders = [path.resolve(workspaceRoot, "packages/shared")];

// Let Metro resolve workspace packages from the root node_modules
// (pnpm stores packages in the root .pnpm store via symlinks)
config.resolver.nodeModulesPaths = [
  path.resolve(projectRoot, "node_modules"),
  path.resolve(workspaceRoot, "node_modules"),
];

// Make sure Metro can resolve the @alice/shared workspace package
config.resolver.extraNodeModules = {
  "@alice/shared": path.resolve(workspaceRoot, "packages/shared"),
};

// Redirect @babel/runtime/regenerator → @babel/runtime/helpers/regenerator
// because @babel/runtime@8 removed the root regenerator.js and only exposes it under helpers/
const origResolveRequest = config.resolver.resolveRequest;
config.resolver.resolveRequest = (context, moduleName, platform) => {
  if (moduleName === "@babel/runtime/regenerator") {
    return context.resolveRequest(
      context,
      "@babel/runtime/helpers/regenerator",
      platform,
    );
  }
  return origResolveRequest
    ? origResolveRequest(context, moduleName, platform)
    : context.resolveRequest(context, moduleName, platform);
};

module.exports = config;
