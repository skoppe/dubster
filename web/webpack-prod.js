var path = require("path");
var webpack = require("webpack");

module.exports = {
	module: {
		loaders: [
			{
				test: /\.js$/,
				include: /src/,
				exclude: /(bower_components|node_modules)/,
				loader: 'babel',
				query: {
					cacheDirectory: true,
				},
			},
		],
		noParse: [],
		preLoaders: []
	},
	plugins: [
		new webpack.DefinePlugin({
			'process.env.NODE_ENV': JSON.stringify('production'),
			'process.env.REACT_SYNTAX_HIGHLIGHTER_LIGHT_BUILD': true
		}),
		new webpack.optimize.DedupePlugin(),
	    new webpack.LoaderOptionsPlugin({
	      minimize: true,
	      debug: false
	    }),
		new webpack.optimize.UglifyJsPlugin({
			compressor: { warnings: false },
		}),
		function() {
			this.plugin("done", function(stats) {
				var fs = require("fs")
				var content = fs.readFileSync(
			        path.join(__dirname, "../public", "index.html"),
			        {encoding:"utf-8"}
				).replace(/bundle\.[a-z0-9]+\.js/,"bundle."+stats.hash+".js")
				fs.writeFileSync(
			        path.join(__dirname, "../public", "index.html"),
			        content
			    )
			})
		}
	],
	entry: { app: ['./src/main.js'] },
	output: {
		path: path.resolve(__dirname, '../public'),
		publicPath: '/public/',
		filename: 'bundle.[hash].js'
	}
};