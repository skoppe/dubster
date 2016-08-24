var path = require("path");
var webpack = require('webpack');

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
	devtool: 'inline-source-map',
	plugins: [
		new webpack.optimize.OccurenceOrderPlugin(),
		new webpack.DefinePlugin({
			'process.env.NODE_ENV': JSON.stringify('development'),
		})
	],
	entry: { app: ['./src/main.js'] },
	output: {
		path: path.resolve(__dirname, '../public'),
		publicPath: '/public/',
		filename: 'bundle.js'
	}
}