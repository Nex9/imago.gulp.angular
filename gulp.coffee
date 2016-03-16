gulp            = require 'gulp'
plugins         = require('gulp-load-plugins')()
browserSync     = require 'browser-sync'

runSequence     = require 'run-sequence'

modRewrite      = require 'connect-modrewrite'
exec            = require('child_process').exec

_               = require 'lodash'
through         = require 'through2'
path            = require 'path'
modifyFilename  = require 'modify-filename'

latestVersion   = require 'latest-version'
ThemeUpload     = require './tasks/themeUpload'
TemplateUpload  = require './tasks/templateUpload'
ThemeTests      = require './tasks/themeTests'
fs              = require 'fs'
crypto          = require 'crypto'
YAML            = require 'js-yaml'
del             = require 'del'
utils           = require './tasks/themeUtils'
pkg             = require './package.json'
config          = require '../../gulp'

yamlOpts = YAML.safeLoad(fs.readFileSync(config.dest + '/theme.yaml'))

gulp.task 'sass', ->
  gulp.src(config.paths.sass)
    .pipe plugins.plumber({errorHandler: utils.reportError})
    .pipe plugins.if plugins.util.env.imagoEnv isnt 'production', plugins.sourcemaps.init()
    .pipe plugins.if plugins.util.env.imagoEnv is 'dev', plugins.sass({quiet: true, outputStyle: 'expanded'}), plugins.sass({quiet: true, outputStyle: 'compressed'})
    .pipe plugins.autoprefixer('last 4 versions')
    .pipe plugins.concat config.targets.css
    .pipe plugins.if plugins.util.env.imagoEnv isnt 'production', plugins.sourcemaps.write()
    .pipe gulp.dest config.dest
    .pipe browserSync.reload(stream: true)
    .pipe plugins.rename('application.min.css')
    .pipe gulp.dest config.dest
    .pipe plugins.gzip()
    .pipe plugins.plumber.stop()
    .pipe gulp.dest config.dest

gulp.task 'coffee', ->
  gulp.src config.paths.coffee
    .pipe plugins.plumber({errorHandler: utils.reportError})
    .pipe plugins.ngClassify(
      constant:
        format: 'camelCase'
        prefix: ''
      controller:
        format: 'camelCase'
        suffix: ''
      factory:
        format: 'camelCase'
      filter:
        format: 'camelCase'
      provider:
        format: 'camelCase'
        suffix: ''
      service:
        format: 'camelCase'
        suffix: ''
      value:
        format: 'camelCase'
      )
    .pipe plugins.coffee(
      bare: true
    ).on('error', utils.reportError)
    .pipe plugins.coffeelint()
    .pipe plugins.concat config.targets.coffee
    .pipe gulp.dest config.dest

gulp.task 'jade', ->
  gulp.src config.paths.jade
    .pipe plugins.plumber({errorHandler: utils.reportError})
    .pipe plugins.if(/[.]jade$/, plugins.jade({locals: {}}).on('error', utils.reportError))
    .pipe plugins.angularTemplatecache(
      standalone: true
      root: "/#{config.src}/"
      module: 'templatesApp'
    )
    .pipe plugins.concat config.targets.jade
    .pipe gulp.dest config.dest

gulp.task 'sketch', ->
  return unless config.paths.sketch
  gulp.src config.paths.sketch
    .pipe plugins.plumber({errorHandler: utils.reportError})
    .pipe plugins.sketch(
      export: 'artboards'
      saveForWeb: true
      trimmed: false)
    .pipe gulp.dest "#{config.dest}/i"

gulp.task 'scripts', ->
  env = plugins.util.env?.env or 'default'
  if _.isArray config.paths.envSpecJs?[env]
    config.paths.libs = config.paths.envSpecJs[env].concat config.paths.libs
  gulp.src config.paths.libs
    .pipe plugins.plumber({errorHandler: utils.reportError})
    .pipe plugins.concat config.targets.scripts
    .pipe gulp.dest config.dest

gulp.task 'index', ->
  return unless config.paths.index
  if plugins.util.env.imagoEnv is 'dev'
    YamlHeader = '<script type="text/javascript">window.yaml = ' +
            JSON.stringify(yamlOpts) +
            '</script>'

  gulp.src config.paths.index
    .pipe plugins.plumber(
      errorHandler: utils.reportError
    )
    .pipe plugins.jade(
      locals: {}
      pretty: true
      ).on('error', utils.reportError)

    .pipe(plugins.if(plugins.util.env.imagoEnv is 'dev', plugins.injectString.after('<head>', YamlHeader)))
    .pipe gulp.dest config.dest

gulp.task 'combine', ->
  rethrow = (err, filename, lineno) -> throw err

  files = [
    config.targets.scripts
    config.targets.coffee
    config.targets.jade
  ]

  sources = files.map (file) -> "#{config.dest}/#{file}"

  gulp.src sources
    .pipe plugins.if plugins.util.env.imagoEnv isnt 'production', plugins.sourcemaps.init()
    .pipe plugins.concat config.targets.js
    .pipe plugins.if plugins.util.env.imagoEnv isnt 'production', plugins.sourcemaps.write "./maps"
    .pipe gulp.dest config.dest
    .pipe browserSync.reload(stream:true)

gulp.task 'js', ['scripts', 'coffee', 'jade'], (next) ->
  next()

gulp.task 'compile', ['index', 'sass', 'js', 'sketch'], (cb) ->
  runSequence 'combine', cb

gulp.task 'browser-sync', ->
  options =
    server:
      baseDir: "#{config.dest}"
      middleware: [
        modRewrite ['^([^\\.]+)(\\?.+)?$ /index.html [L]']
      ]
    debugInfo: false
    notify: false

  if _.isPlainObject config.browserSync
    _.assign options, config.browserSync

  browserSync.init ["#{config.dest}/index.html"], options

gulp.task 'watch', ->
  plugins.util.env.imagoEnv = 'dev'
  runSequence 'import-assets', 'compile', 'browser-sync', ->
    gulp.watch "#{config.dest}/*.jade", ->
      gulp.start('index')

    gulp.watch ['css/*.sass', "#{config.src}/**/*.sass", 'bower_components/imago/**/*.sass'], ->
      gulp.start('sass')

    gulp.watch config.paths.libs, ->
      gulp.start('scripts')

    gulp.watch config.paths.jade, ->
      gulp.start('jade')

    if config.paths.sketch
      gulp.watch config.paths.sketch, ->
        gulp.start('sketch')

    gulp.watch config.paths.coffee, ->
      gulp.start('coffee')

    files = [config.targets.scripts, config.targets.jade, config.targets.coffee]
    sources = ("#{config.dest}/#{file}" for file in files)

    gulp.watch sources, ->
      gulp.start('combine')

    gulp.watch 'gulp.coffee', ->
      delete require.cache[require.resolve('../../gulp')]
      config = require '../../gulp'
      gulp.start('scripts')

gulp.task 'bower', (cb) ->
  exec 'bower install; bower update', (err, stdout, stderr) ->
    console.log 'result: ' + stdout
    console.log 'exec error: ' + err if err
    cb()

gulp.task 'npm', (cb) ->
  exec 'npm update', (error, stdout, stderr) ->
    console.log 'result: ' + stdout
    console.log 'exec error: ' + err if err
    cb()

gulp.task 'import-assets', (cb) ->
  return cb() unless config.paths.importAssets
  for item in config.paths.importAssets
    continue unless _.isPlainObject item
    gulp.src(item.src)
      .pipe(plugins.flatten())
      .pipe(gulp.dest(item.dest))

  cb()

gulp.task 'update', ['npm', 'bower'], (cb) ->
  cb()

gulp.task 'minify', ->
  gulp.src "#{config.dest}/#{config.targets.js}"
    .pipe plugins.uglify
      mangle: false
    .pipe plugins.rename('application.min.js')
    .pipe gulp.dest config.dest
    .pipe plugins.gzip()
    .pipe gulp.dest config.dest

gulp.task 'build', (cb) ->
  plugins.util.env.imagoEnv = 'production'
  runSequence 'import-assets', 'compile', 'minify', cb


gulp.task 'check-update', ->
  latestVersion pkg.name, (err, version) ->
    if version isnt pkg.version
      utils.reportError({message: "There is a newer version for the imago-gulp-angular package available (#{version})."}, 'Update Available')

gulp.task 'deploy', ['build', 'customsass'], ->
  gulp.start 'check-update', ->
    ThemeUpload(config.dest)

gulp.task 'deploy-templates', ->
  TemplateUpload(config.dest)

# START Custom Sass Developer

gulp.task 'customsass', ->
  return 'no path for customSass found' unless config.paths.customSass
  gulp.src(config.paths.customSass)
    .pipe plugins.plumber({errorHandler: utils.reportError})
    .pipe plugins.sourcemaps.init()
    .pipe plugins.sass({indentedSyntax: true, quiet: true})
    .pipe plugins.autoprefixer('last 4 versions')
    .pipe plugins.concat config.targets.customCss
    .pipe plugins.sourcemaps.write()
    .pipe gulp.dest config.dest
    .pipe browserSync.reload(stream: true)
    .pipe plugins.rename('custom.min.css')
    .pipe plugins.gzip()
    .pipe plugins.plumber.stop()
    .pipe gulp.dest config.dest

gulp.task 'watch-customsass', ->
  return 'no path for customSass found' unless config.paths.customSass
  options =
    files: ["#{config.dest}/#{config.targets.customCss}"]
    proxy: "https://#{yamlOpts.tenant}.imago.io/account/checkout/--ID--",
    serveStatic: [config.dest]
    rewriteRules: [
      {
        match: /(latest\/custom\.min\.css)/
        fn: (match) ->
          return config.targets.customCss
      }
    ]

  browserSync.init options
  gulp.watch(config.paths.customSass, ['customsass'])

# END Custom Sass Developer

# START Tests

gulp.task 'karma', (cb) ->
  ThemeTests(gulp, plugins).karma(config, cb)

# END Tests

# Start Revisions

replaceIndex = (replacement) ->
  mutables = []
  changes = []

  return through.obj ((file, enc, cb) ->
    ext = path.extname(file.path)
    if ext is '.json'
      content = file.contents.toString('utf8')
      json = JSON.parse(content)
      changes.push json
    else
      unless file.isNull()
        mutables.push file
    cb()
  ), (cb) ->
    mutables.forEach (file) =>
      src = file.contents.toString('utf8')
      changes.forEach (change) =>
        for key, value of change
          if config.paths.cdn
            env = plugins.util.env?.env or 'default'
            key = "/#{key}"
            value = "#{config.paths.cdn[env]}#{value}"
          key = key.replace replacement, ''
          src = src.replace(key, value)
      file.contents = new Buffer(src)
      @push file
    cb()

gulp.task 'rev-inject', (cb) ->
  gulp.src(["#{config.dest}/*.json", "#{config.dest}/*.html"])
    .pipe replaceIndex('.min')
    .pipe gulp.dest config.dest

gulp.task 'rev-clean', ->
  del("#{config.dest}/**/*.min.*")

gulp.task 'rev-create', ->
  gulp.src(["#{config.dest}/**/*.min.*"])
  .pipe plugins.rev()
  .pipe through.obj((file, enc, cb) ->
    if config.revVersion
      file.path = modifyFilename(file.revOrigPath, (name, ext) ->
        return "#{config.revVersion}-#{name}#{ext}"
      )
      cb null, file
    else
      checksum = (str, algorithm, encoding) ->
        return crypto
          .createHash(algorithm || 'md5')
          .update(str, 'utf8')
          .digest(encoding || 'hex')

      fs.readFile file.revOrigPath, (err, data) ->
        file.path = modifyFilename(file.revOrigPath, (name, ext) ->
          return "#{checksum(data)}-#{name}#{ext}"
        )
        cb null, file
    return
  )
  .pipe gulp.dest config.dest
  .pipe plugins.rev.manifest()
  .pipe gulp.dest config.dest

gulp.task 'rev', (cb) ->
  runSequence 'rev-clean', 'build', 'rev-create', 'rev-inject', cb

# End revisions

gulp.task 'default', ['watch']

module.exports = gulp
