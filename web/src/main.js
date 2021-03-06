require('babel-polyfill');
import injectTapEventPlugin from 'react-tap-event-plugin';
//Needed for onTouchTap
//Can go away when react 1.0 release
//Check this repo:
//https://github.com/zilverline/react-tap-event-plugin
injectTapEventPlugin();

import ReactDOM from "react-dom"
import {default as React} from "react";
import {store} from './store.js';
import { Provider } from 'react-redux';
import {
  default as canUseDOM,
} from "can-use-dom";
import Components from './components';
// import Podcasts from './components/podcasts.js';
// import Playlists from './components/playlists.js';
import { IndexRoute, Router, Route, browserHistory, Redirect } from 'react-router'
import { syncHistoryWithStore } from 'react-router-redux'

const history = syncHistoryWithStore(browserHistory, store)

let container = document.getElementById('app');
container && canUseDOM && ReactDOM.render(
  <Provider store={store}>
  	<Router history={history}>
      <Route path="/" component={Components.App}>
      	<IndexRoute component={Components.Dashboard}/>
      	<Route path="/jobset/:jobset" component={Components.JobSet}/>
      	<Route path="/jobset/:jobset/job/:job" component={Components.Job}/>
      	<Route path="/jobset/:from/compare/:to" component={Components.JobSetCompare}/>
      	<Route path="/packages" component={Components.Packages}/>
      	<Route path="/packages/:package" component={Components.Package}/>
      	<Redirect from="/index.html" to="/" />
      </Route>
    </Router>
  </Provider>,
  container
)

      	// <Route path="/job/:job" component={Components.Job}/>
