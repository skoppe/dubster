// import * as actions from './actions.js';
import Immutable from 'immutable';

/*const searchDefaults = Immutable.fromJS({
		results: [],
		query: null,
		itemsLoaded: null,
		pageSize: 12,
		totalItems: null,
		status: null
	});
function reduceSearch(search = searchDefaults, action)
{
	switch(action.type)
	{
		case actions.SEARCH_PODCAST_START:
			return search.set('status','loading');
		case actions.SEARCH_PODCAST_SUCCESS:
			search = search.set('status','success');
			let {itemsLoaded, results, totalItems, query} = action.response;
			return search.merge(Immutable.fromJS({itemsLoaded, results, totalItems, query}));
		case actions.SEARCH_PODCAST_FAILED:
			let {status = 'failed', xhrStatus, code, message} = action;
			return search.merge(Immutable.fromJS({status,xhrStatus,code,message}));
	}
	return search;
}*/
export default {
}