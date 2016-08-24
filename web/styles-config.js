var less = require('gulp-less');
var gutil = require('gulp-util');

module.exports = {
  bundle: {
    "styles": {
      styles: ['./styles/app.less'],
      options: {
        transforms: {
          styles: function()
          {
            var l = less.apply(this,arguments);
            l.on('error',function(e){
              gutil.log(e);
              // only in development continue stream (if we don't then the gulp-watch will stop watching and we have to restart the whole thing)
              // in staging or production we obviously want to stop
              if (process.env.NODE_ENV == 'development') 
                this.emit('end');
            });
            return l;
          }
        },
        maps: false,
        rev: process.env.NODE_ENV == 'development'
      }
    }
  }
};