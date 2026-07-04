const { getDefaultConfig } = require("@expo/metro-config");

const projectRoot = __dirname;
const config = getDefaultConfig(projectRoot);

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
