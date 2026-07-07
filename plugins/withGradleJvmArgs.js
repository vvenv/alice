const { withGradleProperties } = require("@expo/config-plugins");

/**
 * Config plugin to add JVM args for Java 17+ compatibility.
 * Required when building with Java 17+ to allow CMake native access.
 */
const withGradleJvmArgs = (config) => {
  return withGradleProperties(config, (config) => {
    const properties = config.modResults;

    const setProperty = (key, value) => {
      const existing = properties.find((p) => p.key === key);
      if (existing) {
        existing.value = value;
      } else {
        properties.push({ type: "property", key, value });
      }
    };

    setProperty(
      "org.gradle.jvmargs",
      "-Xmx4096m -XX:MaxMetaspaceSize=1024m --enable-native-access=ALL-UNNAMED -Dfile.encoding=UTF-8"
    );

    return config;
  });
};

module.exports = withGradleJvmArgs;
