import Immutable from 'immutable';

const jobSetsDefault = Immutable.fromJS({
	loaded: 0,
	eof: null,
	status: null,
	errorCode: null,
	errorMessage: null,
	data: []
});
function jobSets(state = jobSetsDefault, action)
{
	switch(action.type)
	{
		case 'QUERY_JOBSETS_START':
			return state.set('status','loading')
		case 'QUERY_JOBSETS_SUCCESS':
			var {status = 'loaded', items, skip, limit} = action.data
			return state
				.set('data',state.get('data').concat(Immutable.fromJS(items)))
				.merge(Immutable.fromJS({status, loaded: skip+limit, eof: items.length != limit}))
		case 'QUERY_JOBSETS_FAILED':
			var {status = 'failed', errorCode, errorMessage} = action.data
			return state.merge(Immutable.fromJS({status,errorCode,errorMessage}))
		case 'JOBSETS_UPDATE':
			var key = state.get('data').findKey(item=>item.get('_id') == action.data.selector._id)
			state = state.setIn(['data',key],state.getIn(['data',key]).merge(Immutable.fromJS(action.data.updates.$set)))
			return state
		case 'JOBSETS_APPEND':
			return state.get('data').unshift(action.data)
	}
	return state
}
export default {
	jobSets
}