{{flutter_js}}
{{flutter_build_config}}

const serviceWorkerVersion = {{flutter_service_worker_version}};

function withVersion(path) {
  if (!path || !serviceWorkerVersion) {
    return path;
  }

  const separator = path.includes('?') ? '&' : '?';
  return `${path}${separator}v=${encodeURIComponent(serviceWorkerVersion)}`;
}

_flutter.buildConfig = {
  ..._flutter.buildConfig,
  builds: _flutter.buildConfig.builds.map((build) => {
    if (!build.mainJsPath) {
      return build;
    }
    return {
      ...build,
      mainJsPath: withVersion(build.mainJsPath),
    };
  }),
};

_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion,
  },
});
