var gulp = require("gulp");
var gutil = require("gulp-util");
var webpack = require("webpack");
var WebpackDevServer = require("webpack-dev-server");
var webpackDevConfig = require("./webpack-dev.js");
var webpackProdConfig = require("./webpack-prod.js");
var bundle = require('gulp-bundle-assets');
var path = require("path");

// The development server (the recommended option for development)
gulp.task("default", ["webpack-dev-server", "less-watch"]);

// Production build
gulp.task("build", ["webpack:build", "less"]);

gulp.task("webpack:build", function(callback) {
	// run webpack
	webpack(webpackProdConfig, function(err, stats) {
		if(err) throw new gutil.PluginError("webpack:build", err);
		gutil.log("[webpack:build]", stats.toString({
			colors: true
		}));
		callback();
	});
});

gulp.task("webpack-dev-server", function(callback) {
	// modify some webpack config options
	var myConfig = Object.create(webpackDevConfig);
	myConfig.devtool = "eval";
	myConfig.debug = true;

	// Start a webpack-dev-server
	new WebpackDevServer(webpack(myConfig), {
		publicPath: "/" + myConfig.output.publicPath,
		stats: {
			colors: true
		},
		contentBase: "../public",
		historyApiFallback: {
    		rewrites: [
    			// handle rev from production
        		{ from: /bundle\.[a-z0-9]*\.js$/, to: '/bundle.js' }
        	]
        },
		hot: false
	}).listen(8080, "localhost", function(err) {
		if(err) throw new gutil.PluginError("webpack-dev-server", err);
		gutil.log("[webpack-dev-server]", "http://localhost:8080/webpack-dev-server/index.html");
	});
});

gulp.task('less', function() {
	return gulp.src('./styles-config.js')
		.pipe(bundle())
		.pipe(bundle.results({dest:'./',pathPrefix:'/'}))
		.pipe(gulp.dest('../public/'))
		.on('end',function(){
			var fs = require("fs")
			var bundles = JSON.parse(fs.readFileSync("./bundle.result.json"))
			var name = bundles.styles.styles.match(/styles-[0-9a-zA-Z]+\.css/)[0]
			var content = fs.readFileSync(
			    path.join(__dirname, "../public", "index.html"),
			    {encoding:"utf-8"}
			).replace(/styles-[0-9a-zA-Z]+\.css/,name)
			fs.writeFileSync(
			    path.join(__dirname, "../public", "index.html"),
			    content
			)
		})
});

gulp.task('less-watch', function()
{
	return gulp.watch(['styles/**/*.less'],['less']);
});