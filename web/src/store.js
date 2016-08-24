import { createStore, combineReducers, applyMiddleware } from 'redux';
import reducers from './reducers.js';
import { Router, Route, browserHistory } from 'react-router'
import { syncHistoryWithStore, routerReducer } from 'react-router-redux'
import thunk from 'redux-thunk';
// import persistence from './persistence.js'

// on pageload we fetch persisted state
// let persistedState = persistence.initialState;

const reducer = combineReducers(Object.assign({}, reducers, {
	routing: routerReducer
}))

let storeFactory = applyMiddleware(
		thunk
		// persistence.persistenceMiddleware
	)(createStore);

let store = storeFactory(reducer/*, persistedState*/);

export {store};