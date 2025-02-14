const esbuild = require('esbuild')

esbuild.build({
  entryPoints: ['app/javascript/application.js', 'app/javascript/device_fingerprint.js'],
  bundle: true,
  sourcemap: true,
  outdir: 'app/assets/builds',
  publicPath: '/assets',
  loader: {
    '.js': 'jsx',
    '.jsx': 'jsx'
  },
  resolveExtensions: ['.js', '.jsx', '.ts', '.tsx'],
  alias: {
    '@': './app/javascript'
  }
}).catch(() => process.exit(1))
